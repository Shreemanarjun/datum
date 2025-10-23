import 'package:example/data/task/adapters/hive_local_adapter.dart';
import 'package:example/data/task/entity/task.dart';

class TaskLocalAdapter extends HiveLocalAdapter<Task> {
  TaskLocalAdapter()
      : super(
          entityBoxName: "task",
          fromMap: Task.fromMap,
        );
}
