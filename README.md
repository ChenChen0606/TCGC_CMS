# clinicmanagementsystem

TCGC Clinic Management System (Flutter + Supabase).

## Setup

### Supabase credentials

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at build/run time.

1. Copy `.env.example` to `.env` and fill in your project URL and anon key
   (the publishable key is safe to ship in the client; the `service_role`
   key must NEVER be used in the app):
   ```json
   {
     "SUPABASE_URL": "https://your-project-ref.supabase.co",
     "SUPABASE_ANON_KEY": "your-publishable-anon-key"
   }
   ```
   `.env` is git-ignored so credentials are not committed.

### Run

```sh
flutter run --dart-define-from-file=.env
```

### Apply database migrations

With the Supabase CLI linked to the project:

```sh
supabase db push
```

## Resources

- [Flutter documentation](https://docs.flutter.dev/)
- [Supabase for Flutter](https://supabase.com/docs/reference/dart/introduction)
