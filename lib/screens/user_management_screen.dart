import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/media_provider.dart';
import '../services/user_account_service.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        final users = provider.users;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9B3FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFFE9B3FF), size: 23),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'User Management',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${users.length} account${users.length == 1 ? '' : 's'} ready for Android login',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _showCreateDialog(context, provider),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Create User'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE9B3FF),
                      side: BorderSide(color: const Color(0xFFE9B3FF).withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFAAC7FF).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFAAC7FF).withValues(alpha: 0.12)),
                ),
                child: const Text(
                  'Accounts created here can authenticate through the media server login endpoint when the Android app is wired up.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? const _EmptyUsers()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _UserTile(
                          user: users[index],
                          onToggle: (enabled) => provider.setUserEnabled(users[index].id, enabled),
                          onReset: () => _showResetDialog(context, provider, users[index]),
                          onDelete: () => _confirmDelete(context, provider, users[index]),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context, MediaProvider provider) async {
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final passwordController = TextEditingController(text: provider.generateUserPassword());
    bool showPassword = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E22),
              title: const Text('Create User', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogField(usernameController, 'Username', Icons.person_rounded),
                    const SizedBox(height: 12),
                    _dialogField(displayNameController, 'Display name', Icons.badge_rounded),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: !showPassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Temporary password',
                        Icons.password_rounded,
                        suffix: IconButton(
                          onPressed: () => setState(() => showPassword = !showPassword),
                          icon: Icon(showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white38),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => passwordController.text = provider.generateUserPassword()),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                          label: const Text('Generate'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: passwordController.text));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final user = await provider.createUserAccount(
                        username: usernameController.text,
                        displayName: displayNameController.text,
                        password: passwordController.text,
                      );
                      Clipboard.setData(ClipboardData(
                        text: 'Username: ${user.username}\nPassword: ${passwordController.text}',
                      ));
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User created and credentials copied')),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    displayNameController.dispose();
    passwordController.dispose();
  }

  Future<void> _showResetDialog(BuildContext context, MediaProvider provider, UserAccount user) async {
    final passwordController = TextEditingController(text: provider.generateUserPassword());
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: Text('Reset ${user.username}', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: passwordController,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('New password', Icons.password_rounded),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: passwordController.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password copied')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await provider.resetUserPassword(user.id, passwordController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password reset')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    passwordController.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, MediaProvider provider, UserAccount user) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Delete User?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete ${user.username}? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteUserAccount(user.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white38),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE9B3FF)),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserAccount user;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  const _UserTile({
    required this.user,
    required this.onToggle,
    required this.onReset,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final created = DateFormat('MMM d, yyyy').format(user.createdAt);
    final lastLogin = user.lastLoginAt == null
        ? 'Never'
        : DateFormat('MMM d, yyyy h:mm a').format(user.lastLoginAt!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: (user.isEnabled ? const Color(0xFFE9B3FF) : Colors.white24).withValues(alpha: 0.18),
            child: Text(
              user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${user.username}  |  Created $created  |  Last login: $lastLogin',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (user.isEnabled ? const Color(0xFF42E355) : Colors.white38).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              user.isEnabled ? 'ACTIVE' : 'DISABLED',
              style: TextStyle(
                color: user.isEnabled ? const Color(0xFF42E355) : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: user.isEnabled,
            onChanged: onToggle,
            activeColor: const Color(0xFFE9B3FF),
          ),
          IconButton(
            tooltip: 'Reset password',
            onPressed: onReset,
            icon: const Icon(Icons.key_rounded, color: Colors.white54, size: 20),
          ),
          IconButton(
            tooltip: 'Delete user',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_add_rounded, color: Colors.white12, size: 64),
          SizedBox(height: 16),
          Text('No users yet', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Create accounts here and hand out the generated credentials.', style: TextStyle(color: Colors.white30)),
        ],
      ),
    );
  }
}
