import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.prominent = false});
  final bool prominent;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconTile(icon: Icons.ramen_dining_outlined, size: prominent ? 52 : 36),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          'Smart Canteen',
          style: TextStyle(
            fontSize: prominent ? 24 : 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 56});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: lightOrange,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: primaryOrange, size: size * .48),
  );
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.child,
    this.back = false,
    this.footer,
  });
  final Widget child;
  final Widget? footer;
  final bool back;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                minHeight: constraints.maxHeight - 40,
              ),
              child: Column(
                mainAxisAlignment: footer == null
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (back)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton.outlined(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, size: 20),
                      ),
                    ),
                  child,
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: footer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class FormHeading extends StatelessWidget {
  const FormHeading(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: mutedText, fontSize: 13)),
      const SizedBox(height: 28),
    ],
  );
}

class AppField extends StatefulWidget {
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.password = false,
    this.keyboardType,
    this.autofillHints,
    this.enabled = true,
    this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool password, enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final VoidCallback? onSubmitted;
  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          validator: widget.validator,
          obscureText: widget.password && hidden,
          autocorrect: false,
          enableSuggestions: !widget.password,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.onSubmitted == null
              ? TextInputAction.next
              : TextInputAction.done,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            hintText: widget.label,
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: hidden ? 'Show password' : 'Hide password',
                    onPressed: widget.enabled
                        ? () => setState(() => hidden = !hidden)
                        : null,
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: mutedText,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: onPressed == null
          ? []
          : [
              BoxShadow(
                color: primaryOrange.withValues(alpha: .12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
    ),
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primaryOrange,
              ),
            )
          : Text(label),
    ),
  );
}

class ErrorMessage extends StatelessWidget {
  const ErrorMessage(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}
