import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSecurityDialog extends StatefulWidget {
  const SupabaseSecurityDialog({super.key});

  @override
  State<SupabaseSecurityDialog> createState() => _SupabaseSecurityDialogState();
}

class _SupabaseSecurityDialogState extends State<SupabaseSecurityDialog> {
  final supabaseURL = "";
  final supabaseKey = "";

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ShadDialog(
        scrollPadding: EdgeInsets.symmetric(vertical: 12),
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(
          maxWidth: 400,
        ),
        title: Text('Supabase Security'),
        actions: [
          ShadButton(
            child: Text('Save'),
            onPressed: () async {
              try {
                await Supabase.instance.dispose();
              } catch (e) {
                print(e);
              }
              await Supabase.initialize(
                url: supabaseURL,
                anonKey: supabaseKey,
              );
            },
          )
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Supabase URL"),
            SizedBox(height: 8),
            ShadInput(
              placeholder: Text(supabaseURL),
            ),
            SizedBox(height: 16),
            Text("Supabase Key"),
            SizedBox(height: 8),
            ShadInput(
              placeholder: Text(supabaseKey),
              obscureText: true,
              trailing: ShadIconButton(icon: Icon(Icons.visibility)),
            ),
          ],
        ),
      ),
    );
  }
}
