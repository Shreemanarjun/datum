import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/shared/api_client/dio/default_api_interceptor.dart';
import 'package:example/shared/api_client/dio/default_time_response_interceptor.dart';
import 'package:example/shared/api_client/dio/dio_client_provider.dart';
import 'package:example/shared/api_client/dio/form_data_interceptor.dart';

import 'package:talker_dio_logger/talker_dio_logger.dart';

void main() {
  group("dio Client Provider", () {
    test('expect dio.baseUrl should be "https://randomuser.me/api/"', () {
      final container = ProviderContainer();
      final dio = container.read(dioProvider);
      expect(
        dio,
        isA<DioForNative>()
            .having(
              (d) => d.options.baseUrl,
              'default interceptor should be 2',
              equals("https://randomuser.me/api/"),
            )
            .having(
              (d) => d.interceptors.length,
              "Interceptors should be 5",
              equals(5),
            )
            .having(
              (d) => d.interceptors,
              "Contains a time response interceptor",
              containsAll([
                isA<TimeResponseInterceptor>(),
                isA<FormDataInterceptor>(),
                isA<TalkerDioLogger>(),
                isA<DefaultAPIInterceptor>(),
              ]),
            ),
      );
    });
  });
}
