import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/predefined_pictures.dart';
import '../theme/app_theme.dart';

class StallPicture extends StatelessWidget {
  const StallPicture(this.id, {super.key, this.width = 112, this.height = 80});
  final String id;
  final double width, height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.asset(pictureAsset(id), width: width, height: height,
      cacheWidth: 400, fit: BoxFit.cover, semanticLabel: pictureLabel(id),
      errorBuilder: (_, _, _) => SizedBox(width: width, height: height,
        child: const Icon(Icons.image_not_supported_outlined))),
  );
}

/// Returns a draft ID only; neither Confirm nor Cancel writes to Firestore.
Future<String?> chooseStallPicture(BuildContext context, String initial) =>
    showDialog<String>(context: context,
      builder: (_) => _PictureDialog(initial: initial));

class _PictureDialog extends StatefulWidget {
  const _PictureDialog({required this.initial});
  final String initial;
  @override
  State<_PictureDialog> createState() => _PictureDialogState();
}

class _PictureDialogState extends State<_PictureDialog> {
  late String _selected = widget.initial;

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 480,
      height: math.min(600.0, MediaQuery.sizeOf(context).height * .8),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose Picture', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(child: GridView.builder(
            key: const ValueKey('picture-library'),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140, childAspectRatio: .85,
              crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: predefinedPictures.length,
            itemBuilder: (context, index) {
              final id = predefinedPictures.keys.elementAt(index);
              final selected = id == _selected;
              return Semantics(selected: selected, button: true,
                label: pictureLabel(id),
                child: InkWell(
                  key: ValueKey('picture-$id'),
                  onTap: () => setState(() => _selected = id),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? primaryOrange : Colors.grey.shade300,
                        width: selected ? 3 : 1)),
                    child: Column(children: [
                      Expanded(child: Stack(fit: StackFit.expand, children: [
                        StallPicture(id, width: 140, height: 100),
                        if (selected) const Align(alignment: Alignment.topRight,
                          child: Icon(Icons.check_circle, color: primaryOrange)),
                      ])),
                      const SizedBox(height: 4),
                      Text(pictureLabel(id), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              );
            },
          )),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Confirm'))),
          ]),
        ],
      )),
    ),
  );
}
