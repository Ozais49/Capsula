import 'package:capsula_core/domain/bookmarks/shared_content.dart';
import 'package:capsula/platform/share_intake.dart';

class FakeShareIntake implements ShareIntake {
  FakeShareIntake([this.pending]);

  SharedContent? pending;
  int finishCalls = 0;
  int moveToBackgroundCalls = 0;

  @override
  Future<SharedContent?> take() async {
    final content = pending;
    pending = null;
    return content;
  }

  @override
  Future<void> moveToBackground() async => moveToBackgroundCalls++;

  @override
  Future<void> finish() async => finishCalls++;
}
