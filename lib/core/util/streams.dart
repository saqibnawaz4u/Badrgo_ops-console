import 'dart:async';

/// Interleaves several streams into one; cancelling it cancels all of them.
Stream<T> mergeStreams<T>(List<Stream<T>> streams) => Stream.multi((controller) {
      final subscriptions = [
        for (final s in streams) s.listen(controller.add, onError: controller.addError),
      ];
      controller.onCancel = () => Future.wait(subscriptions.map((s) => s.cancel()));
    });
