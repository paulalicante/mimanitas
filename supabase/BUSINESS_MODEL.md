# Business Model Enforcement

## User Type Separation

Mi Manitas enforces a strict separation between two user types at the database level:

### Helper (Manitas)
- **Free forever** - No subscription required
- Can post their availability (when they're free to work)
- Can apply to jobs posted by seekers
- Can message and receive reviews
- This is the **supply side** you need to attract to make the platform work

### Seeker (Employer)
- **Pays subscription** - €10/month (after free trial)
- Can post jobs/needs
- Can review applications from helpers
- Can hire and pay helpers
- This is the **revenue side** of the business

## Why This Matters

This separation is critical for:
1. **Revenue model** - Only seekers pay, helpers are free
2. **Spanish labor law compliance** - Platform is a bulletin board, not an employer
3. **Clear value proposition** - Each side knows what they get

## Database Enforcement

The schema enforces this through:
- `user_type` field must be 'helper' OR 'seeker' (not 'both')
- RLS policies prevent helpers from posting jobs
- RLS policies prevent seekers from posting availability or applying to jobs
- Subscription tracking only for seekers

## Implementation in Signup Flow

When users sign up, they must choose their role. Update `signup_screen.dart`:

```dart
// Add to signup form
String _selectedUserType = 'helper'; // Default

// In the form, add a role selector:
Column(
  children: [
    Text('¿Qué quieres hacer?', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),

    // Helper option
    RadioListTile<String>(
      title: const Text('Quiero ayudar'),
      subtitle: const Text('Ofrece tus habilidades cuando tengas tiempo libre (Gratis)'),
      value: 'helper',
      groupValue: _selectedUserType,
      onChanged: (value) {
        setState(() => _selectedUserType = value!);
      },
    ),

    // Seeker option
    RadioListTile<String>(
      title: const Text('Necesito ayuda'),
      subtitle: const Text('Publica trabajos y contrata manitas (€10/mes después del periodo de prueba)'),
      value: 'seeker',
      groupValue: _selectedUserType,
      onChanged: (value) {
        setState(() => _selectedUserType = value!);
      },
    ),
  ],
)

// In the signup call, pass user_type:
await supabase.auth.signUp(
  email: _emailController.text.trim(),
  password: _passwordController.text,
  data: {
    'name': _nameController.text.trim(),
    'user_type': _selectedUserType, // IMPORTANT!
  },
);
```

## Login Screen Changes

The login screen doesn't need changes - the user's type is stored in their profile and will be loaded after login.

## Home Screen Changes

After login, check the user's type and show the appropriate interface:

```dart
final user = supabase.auth.currentUser;
final profile = await supabase
  .from('profiles')
  .select('user_type')
  .eq('id', user!.id)
  .single();

if (profile['user_type'] == 'helper') {
  // Show: "Puedo ayudar" button -> Post availability
  // Show: Browse jobs to apply
} else {
  // Show: "Necesito ayuda" button -> Post job
  // Show: Manage my jobs and applications
}
```

## Subscription Management (Phase 2)

For seekers, you'll eventually need to:
1. Integrate Stripe/Mangopay subscriptions
2. Check `subscription_status` before allowing job posts
3. Show subscription UI in settings
4. Handle trial period (currently set to 'free_trial' by default)

During MVP launch (Phase 1), all seekers are on free trial to build volume.

## What If Someone Wants Both Roles?

This is not the expected use case. If it comes up:
- **Option 1:** They create two accounts (one helper, one seeker) with different emails
- **Option 2:** You add a future "Switch role" feature that changes their user_type (but this complicates billing and is not recommended initially)

For MVP, enforce the separation and see if users actually ask for dual roles before building complexity.
