# Teacher access codes

Teacher accounts are no longer self-serve. Registration at `/register/teacher` requires a one-time **Teacher access code**.

## Bootstrap (this folder)

Until at least one Teacher exists, mint codes locally and paste them in Firebase Console:

```powershell
dart run scripts/generate_teacher_access_code.dart
dart run scripts/generate_teacher_access_code.dart 5
```

In Firebase Console → Firestore:

1. Open collection `teacher_access_codes` (create it if needed).
2. Add a document whose **ID** is the printed `documentId` (12 characters, no hyphens).
3. Set fields:
   - `consumed` (boolean): `false`
   - `created_at` (timestamp): now
   - `note` (string, optional): e.g. `capstone bootstrap`

Share the grouped `display` value (for example `7KPM-XR4D-Q2WT`) with the person registering.

## After the first Teacher

Signed-in Teachers can mint additional codes in **Faculties → Invite a faculty member**. Those writes go to the same collection with `created_by` set to the minting Teacher's uid.

Codes are single-use. Consuming a code and creating `users/{uid}` with `role: Teacher` must happen in the same Firestore transaction.
