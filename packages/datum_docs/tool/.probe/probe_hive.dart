import 'package:datum_hive/datum_hive.dart';
import '../snippet_scaffold.dart';

Future<void> main() async {
  final a = HiveLocalAdapter<Task>(entityBoxName: 't', fromMap: Task.fromMap);
  print(a);
}
