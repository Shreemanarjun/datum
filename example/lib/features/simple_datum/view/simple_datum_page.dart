import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class SimpleDatumPage extends ConsumerStatefulWidget {
  const SimpleDatumPage({super.key});

  @override
  ConsumerState<SimpleDatumPage> createState() => _SimpleDatumPageState();
}

class _SimpleDatumPageState extends ConsumerState<SimpleDatumPage> {
  @override
  Widget build(BuildContext context) {
    final simpleDatumAsync = ref.watch(simpleDatumProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Simple Datum"),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: Icon(Icons.add),
      ),
      body: simpleDatumAsync.easyWhen(
        data: (data) {
          return Center(
            child: Text(data.toString()),
          );
        },
      ),
    );
  }
}
