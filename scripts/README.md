# Teacher access codes

Teacher accounts are no longer self-serve. Registration at `/register/teacher` requires a one-time **Teacher access code**.

## Bootstrap (this folder)

Until at least one Teacher exists, mint codes locally and insert them with the
Supabase SQL editor (service role) — never from the client:

```powershell
dart run scripts/generate_teacher_access_code.dart
dart run scripts/generate_teacher_access_code.dart 5
```

```sql
insert into public.teacher_access_codes (code, note)
values ('<documentId>', 'capstone bootstrap');
```

Use the printed `documentId` (12 characters, no hyphens) as `code`.

Share the grouped `display` value (for example `7KPM-XR4D-Q2WT`) with the person registering.

## After the first Teacher

Signed-in Teachers can mint additional codes in **Faculties → Invite a faculty member**. Those go through the `mint_teacher_access_code` RPC, which sets `created_by` to the minting Teacher's user ID.

Codes are single-use. Consuming a code and creating the Teacher profile happen in the same database transaction.
