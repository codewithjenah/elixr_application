// ELIXR privileged operations that need the service role: Storage cleanup for
// account erasure and permanent deletes, and server-side validation of
// uploaded learning materials. Every action verifies the caller's JWT first;
// database functions re-check ownership against that verified identity.
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RECENT_SIGN_IN_MS = 10 * 60 * 1000;
const LIST_PAGE = 100;

type Json = Record<string, unknown>;

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function json(status: number, body: Json): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function validId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

async function rpc<T>(admin: SupabaseClient, fn: string, args: Json): Promise<T> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) {
    const status = error.code === '42501' ? 403 : error.code === 'P0002' ? 404 : 409;
    throw new HttpError(status, error.message);
  }
  return data as T;
}

/** Removes every object under [prefix] (recursively), page by page. */
async function removePrefix(admin: SupabaseClient, bucket: string, prefix: string) {
  const folder = prefix.replace(/\/+$/, '');
  for (;;) {
    const { data, error } = await admin.storage.from(bucket).list(folder, { limit: LIST_PAGE });
    if (error) throw new HttpError(502, 'storage_list_failed');
    if (!data || data.length === 0) return;
    const files: string[] = [];
    for (const entry of data) {
      const path = `${folder}/${entry.name}`;
      if (entry.id === null) {
        await removePrefix(admin, bucket, path);
      } else {
        files.push(path);
      }
    }
    if (files.length > 0) {
      const { error: removeError } = await admin.storage.from(bucket).remove(files);
      if (removeError) throw new HttpError(502, 'storage_remove_failed');
    }
    if (data.length < LIST_PAGE && files.length === data.length) return;
  }
}

async function removeBucketPrefixes(admin: SupabaseClient, prefixes: string[]) {
  for (const entry of prefixes) {
    const split = entry.indexOf(':');
    await removePrefix(admin, entry.slice(0, split), entry.slice(split + 1));
  }
}

async function deleteAccount(admin: SupabaseClient, user: { id: string; last_sign_in_at?: string }) {
  const lastSignIn = user.last_sign_in_at ? Date.parse(user.last_sign_in_at) : 0;
  if (!lastSignIn || Date.now() - lastSignIn > RECENT_SIGN_IN_MS) {
    throw new HttpError(401, 'requires_recent_login');
  }
  const prepared = await rpc<{ objects: Array<{ bucket: string; prefix?: string; path?: string }> }>(
    admin,
    'admin_prepare_account_erasure',
    { p_uid: user.id },
  );
  for (const object of prepared.objects ?? []) {
    if (object.prefix) {
      await removePrefix(admin, object.bucket, object.prefix);
    } else if (object.path) {
      const { error } = await admin.storage.from(object.bucket).remove([object.path]);
      if (error) throw new HttpError(502, 'storage_remove_failed');
    }
  }
  // Rows owned by the account cascade from auth.users.
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) throw new HttpError(502, 'auth_delete_failed');
  return { deleted: true };
}

function detectContentType(bytes: Uint8Array): string | null {
  const starts = (sig: number[], offset = 0) => sig.every((b, i) => bytes[offset + i] === b);
  if (starts([0x25, 0x50, 0x44, 0x46, 0x2d])) return 'application/pdf';
  if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (starts([0x66, 0x74, 0x79, 0x70], 4)) return 'video/mp4';
  return null;
}

async function finalizeMaterialUpload(admin: SupabaseClient, userId: string, uploadId: unknown) {
  if (typeof uploadId !== 'string' || uploadId.length > 64) throw new HttpError(400, 'invalid_payload');
  const claim = await rpc<{ state: string; staging_path?: string; upload?: Json }>(
    admin,
    'admin_claim_material_upload',
    { p_upload_id: uploadId, p_teacher_id: userId },
  );
  const bucket = admin.storage.from('activity-learning-materials');
  if (claim.state !== 'claimed' || !claim.upload) {
    if (claim.staging_path) await bucket.remove([claim.staging_path]);
    return { state: claim.state };
  }
  const upload = claim.upload as {
    staging_path: string;
    assignment_id: string;
    material_id: string;
    declared_content_type: string;
    declared_size_bytes: number;
  };
  const reject = async (reason: string) => {
    await bucket.remove([upload.staging_path]);
    await rpc(admin, 'admin_complete_material_upload', {
      p_upload_id: uploadId,
      p_accepted: false,
      p_final_path: null,
      p_detected_content_type: null,
      p_size_bytes: null,
      p_rejection_reason: reason,
    });
    return { state: 'rejected', rejection_reason: reason };
  };
  const { data: blob, error } = await bucket.download(upload.staging_path);
  if (error || !blob) return await reject('upload_failed');
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (bytes.byteLength !== Number(upload.declared_size_bytes)) return await reject('invalid_size');
  const detected = detectContentType(bytes.subarray(0, 16));
  if (detected !== upload.declared_content_type) return await reject('invalid_content');
  const finalPath = `activity_learning_materials/${upload.assignment_id}/${upload.material_id}`;
  const { error: moveError } = await bucket.move(upload.staging_path, finalPath);
  if (moveError) return await reject('upload_failed');
  try {
    await rpc(admin, 'admin_complete_material_upload', {
      p_upload_id: uploadId,
      p_accepted: true,
      p_final_path: finalPath,
      p_detected_content_type: detected,
      p_size_bytes: bytes.byteLength,
      p_rejection_reason: null,
    });
  } catch (err) {
    // The material was removed or the assignment deleted meanwhile.
    await bucket.remove([finalPath]);
    throw err;
  }
  return { state: 'ready' };
}

async function removeMaterial(client: SupabaseClient, admin: SupabaseClient, body: Json) {
  if (!validId(body.assignment_id) || typeof body.material_id !== 'string') {
    throw new HttpError(400, 'invalid_payload');
  }
  // Runs as the caller so the database authorizes the Teacher and revokes
  // read access before any object is removed.
  const { data, error } = await client.rpc('request_activity_material_removal', {
    p_assignment_id: body.assignment_id,
    p_material_id: body.material_id,
  });
  if (error) throw new HttpError(error.code === '42501' ? 403 : 409, error.message);
  const paths = ((data as { paths?: string[] })?.paths ?? []).filter(Boolean);
  if (paths.length > 0) {
    const { error: removeError } = await admin.storage.from('activity-learning-materials').remove(paths);
    if (removeError) throw new HttpError(502, 'storage_remove_failed');
  }
  await rpc(admin, 'admin_finish_material_removal', { p_material_id: body.material_id });
  return { removed: true };
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const authorization = request.headers.get('Authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'unauthenticated' });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json(401, { error: 'unauthenticated' });
  const user = userData.user;
  const caller = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  let body: Json;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: 'invalid_payload' });
  }

  try {
    switch (body.action) {
      case 'delete_account':
        return json(200, await deleteAccount(admin, user));
      case 'permanent_delete_assignment': {
        if (body.confirmation !== 'DELETE ASSIGNMENT' || !validId(body.assignment_id)) {
          return json(400, { error: 'invalid_confirmation' });
        }
        const result = await rpc<{ prefixes: string[] }>(admin, 'admin_permanent_delete_assignment', {
          p_teacher_id: user.id,
          p_assignment_id: body.assignment_id,
        });
        await removeBucketPrefixes(admin, result.prefixes ?? []);
        return json(200, { deleted: true });
      }
      case 'permanent_delete_classroom': {
        if (body.confirmation !== 'DELETE CLASSROOM' || !validId(body.group_id)) {
          return json(400, { error: 'invalid_confirmation' });
        }
        const result = await rpc<{ prefixes: string[] }>(admin, 'admin_permanent_delete_classroom', {
          p_teacher_id: user.id,
          p_group_id: body.group_id,
        });
        await removeBucketPrefixes(admin, result.prefixes ?? []);
        return json(200, { deleted: true });
      }
      case 'finalize_material_upload':
        return json(200, await finalizeMaterialUpload(admin, user.id, body.upload_id));
      case 'remove_material':
        return json(200, await removeMaterial(caller, admin, body));
      default:
        return json(400, { error: 'unknown_action' });
    }
  } catch (err) {
    if (err instanceof HttpError) return json(err.status, { error: err.code });
    console.error('elixr-admin failed', err instanceof Error ? err.message : 'unknown');
    return json(500, { error: 'internal' });
  }
});
