import 'package:flutter/material.dart';

Future<bool> confirmDeletion(BuildContext context, String name) async =>
    await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete Food?'),
      content: Text('Delete "$name" from your menu? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete Food')),
      ],
    )) ?? false;
