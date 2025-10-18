import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This one is extension `when` extension on AsyncValue
/// with some default loading,error widget and
///  also which also supports custom loading and error widget
extension AsyncDisplay<T> on AsyncValue<T> {
  Widget easyWhen({
    required Widget Function(T data) data,
    Widget Function(Object error, StackTrace stackTrace)? errorWidget,
    Widget Function()? loadingWidget,
    bool skipLoadingOnReload = false,
    bool skipLoadingOnRefresh = true,
    bool skipError = false,
    bool isLinear = false,
    VoidCallback? onRetry,
    bool includedefaultDioErrorMessage = false,
  }) =>
      when(
        data: data,
        error: (error, stackTrace) {
          return errorWidget != null
              ? errorWidget(
                  error,
                  stackTrace,
                )
              : DefaultErrorWidget(
                  isLinear: isLinear,
                  error: error,
                  stackTrace: stackTrace,
                  onRetry: onRetry,
                  includedefaultDioErrorMessage: includedefaultDioErrorMessage,
                );
        },
        loading: () {
          return loadingWidget != null
              ? loadingWidget()
              : DefaultLoadingWidget(
                  isLinear: isLinear,
                );
        },
        skipError: skipError,
        skipLoadingOnRefresh: skipLoadingOnRefresh,
        skipLoadingOnReload: skipLoadingOnReload,
      );
}

/// This class give defaut loading widget
class DefaultLoadingWidget extends StatelessWidget {
  const DefaultLoadingWidget({
    required this.isLinear,
    super.key,
  });
  final bool isLinear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: isLinear
          ? const LinearProgressIndicator()
          : const CircularProgressIndicator.adaptive(),
    );
  }
}

/// This widget supports error messages automatically
class DefaultErrorWidget extends StatelessWidget {
  const DefaultErrorWidget({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
    required this.isLinear,
    required this.includedefaultDioErrorMessage,
    super.key,
  });
  final Object error;
  final StackTrace stackTrace;
  final VoidCallback? onRetry;
  final bool isLinear;
  final bool includedefaultDioErrorMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: isLinear
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorTextWidget(
                  error: error,
                  includedefaultDioErrorMessage: includedefaultDioErrorMessage,
                ),
                if (onRetry != null)
                  Flexible(
                      child: ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Try again '),
                  ))
                else
                  Flexible(
                    child: const Padding(
                      padding: EdgeInsetsGeometry.all(8),
                      child: Text('Try Again later.'),
                    ),
                  ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.red,
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Something went wrong! ',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ErrorTextWidget(
                  error: error,
                  includedefaultDioErrorMessage: includedefaultDioErrorMessage,
                ),
                if (onRetry != null)
                  Flexible(
                    child: ElevatedButton(
                      onPressed: onRetry,
                      child: const Text('Try again '),
                    ),
                  )
                else
                  Flexible(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: const Text('Try Again later.'),
                    ),
                  ),
              ],
            ),
    );
  }
}

///This widgets classes default error messages
class ErrorTextWidget extends StatelessWidget {
  const ErrorTextWidget({
    required this.error,
    required this.includedefaultDioErrorMessage,
    super.key,
  });
  final Object error;
  final bool includedefaultDioErrorMessage;

  @override
  Widget build(BuildContext context) {
    if (includedefaultDioErrorMessage && error is DioException) {
      return DefaultDioErrorWidget(
        dioError: error as DioException,
      );
    }
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Text(
          error.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

///This class used to show error message according to DioException type
class DefaultDioErrorWidget extends StatelessWidget {
  const DefaultDioErrorWidget({
    required this.dioError,
    super.key,
  });
  final DioException dioError;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: switch (dioError.type) {
          DioExceptionType.connectionTimeout => Text(
              'Connection Timeout Error',
              style: TextStyle(color: Colors.red),
            ),
          DioExceptionType.sendTimeout => Text(
              'Unable to connect to the server.Please try again later.',
            ),
          DioExceptionType.receiveTimeout =>
            Text('Check you internet connection reliability.'),
          DioExceptionType.badCertificate =>
            Text('Please update your OS or add certificate.'),
          DioExceptionType.badResponse =>
            Text('Something went wrong.Please try again later.'),
          DioExceptionType.cancel => Text('Request Cancelled'),
          DioExceptionType.connectionError =>
            Text('Unable to connect to server.Please try again later.'),
          DioExceptionType.unknown =>
            Text('Please check your internet connection.'),
        },
      ),
    );
  }
}
