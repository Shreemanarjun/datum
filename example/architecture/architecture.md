# Flutter Project Architecture: Feature-First with Riverpod

This document outlines the architectural principles for our Flutter project, emphasizing a Feature-First approach, robust state management with Riverpod, and explicit error handling using a `Result` type.

## 1. Architectural Layers

Our architecture is structured around distinct layers, each with well-defined responsibilities:

*   **Presentation Layer:** UI components and user interaction handling.
*   **Controller Layer:** Business logic and state management for features.
*   **Data Layer:** Data access, including repositories and data sources.
*   **Core Layer:** Foundational services and utilities shared across the application.
*   **Shared Layer:** Services, utilities, and abstractions shared across features.
* **Const Layer:** global const values.

## 2. Feature-First Architecture

*   **Modular Structure:** Each feature is self-contained, enabling independent development, testing, and scaling.
*   **Clear Boundaries:** Features communicate via well-defined interfaces, minimizing dependencies.
* **Directory Structure:** The application will be structured in different folders.
    * `lib` : main folder for the project.
    * `test` : main folder for testing.
    * `app`: folder for application main view.
    * `const`: folder for constants values.
    * `core`: folder for core functionalities.
    * `features`: folder for all app features.
    * `i18n`: folder for translation.
    * `shared`: folder for shared functionalities.

```
## Outputs 📦

```txt
📦lib
 ┣ 📂app
 ┃ ┣ 📂view
 ┃ ┃ ┗ 📜app.dart
 ┃ ┗ 📜app.dart
 ┣ 📂const
 ┃ ┣ 📜app_urls.dart
 ┃ ┗ 📜resource.dart
 ┣ 📂core
 ┃ ┣ 📂local_storage
 ┃ ┃ ┣ 📜app_storage.dart
 ┃ ┃ ┗ 📜app_storage_pod.dart
 ┃ ┣ 📂router
 ┃ ┃ ┣ 📜auto_route_observer.dart
 ┃ ┃ ┣ 📜router.dart
 ┃ ┃ ┣ 📜router.gr.dart
 ┃ ┃ ┗ 📜router_pod.dart
 ┃ ┗ 📂theme
 ┃ ┃ ┣ 📜app_theme.dart
 ┃ ┃ ┗ 📜theme_controller.dart
 ┣ 📂features
 ┃ ┣ 📂counter
 ┃ ┃ ┣ 📂controller
 ┃ ┃ ┃ ┣ 📂notifier
 ┃ ┃ ┃ ┃ ┗ 📜counter_notifier.dart
 ┃ ┃ ┃ ┗ 📜counter_state_pod.dart
 ┃ ┃ ┣ 📂view
 ┃ ┃ ┃ ┗ 📜counter_page.dart
 ┃ ┃ ┗ 📜counter.dart
 ┃ ┣ 📂splash
 ┃ ┃ ┣ 📂controller
 ┃ ┃ ┃ ┣ 📜box_encryption_key_pod.dart
 ┃ ┃ ┃ ┗ 📜future_initializer.dart
 ┃ ┃ ┗ 📂view
 ┃ ┃ ┃ ┗ 📜splash_view.dart
 ┃ ┗ 📂theme_segmented_btn
 ┃ ┃ ┣ 📂controller
 ┃ ┃ ┃ ┗ 📜selection_theme_pod.dart
 ┃ ┃ ┗ 📂view
 ┃ ┃ ┃ ┗ 📜theme_segmented_btn.dart
 ┣ 📂i18n
 ┃ ┣ 📜en.i18n.json
 ┃ ┣ 📜es.i18n.json
 ┃ ┣ 📜strings.g.dart
 ┃ ┣ 📜strings_en.g.dart
 ┃ ┗ 📜strings_es.g.dart
 ┣ 📂shared
 ┃ ┣ 📂api_client
 ┃ ┃ ┗ 📂dio
 ┃ ┃ ┃ ┣ 📜bad_certificate_fixer.dart
 ┃ ┃ ┃ ┣ 📜default_api_error_handler.dart
 ┃ ┃ ┃ ┣ 📜default_api_interceptor.dart
 ┃ ┃ ┃ ┣ 📜default_time_response_interceptor.dart
 ┃ ┃ ┃ ┣ 📜dio_client_provider.dart
 ┃ ┃ ┃ ┗ 📜form_data_interceptor.dart
 ┃ ┣ 📂exception
 ┃ ┃ ┗ 📜base_exception.dart
 ┃ ┣ 📂extension
 ┃ ┃ ┗ 📜response_success_error_handler.dart
 ┃ ┣ 📂helper
 ┃ ┃ ┗ 📜global_helper.dart
 ┃ ┣ 📂pods
 ┃ ┃ ┣ 📜internet_checker_pod.dart
 ┃ ┃ ┗ 📜translation_pod.dart
 ┃ ┣ 📂riverpod_ext
 ┃ ┃ ┣ 📜asynvalue_easy_when.dart
 ┃ ┃ ┣ 📜cache_extensions.dart
 ┃ ┃ ┣ 📜cancel_extensions.dart
 ┃ ┃ ┣ 📜riverpod_extensions.dart
 ┃ ┃ ┗ 📜riverpod_observer.dart
 ┃ ┗ 📂widget
 ┃ ┃ ┣ 📜app_locale_popup.dart
 ┃ ┃ ┣ 📜no_internet_widget.dart
 ┃ ┃ ┗ 📜responsive_wrapper.dart
 ┣ 📜bootstrap.dart
 ┣ 📜init.dart
 ┣ 📜main.dart
 ┣ 📜main_development.dart
 ┣ 📜main_production.dart
 ┣ 📜main_staging.dart
 ┗ 📜splasher.dart

📦test
 ┣ 📂app
 ┃ ┗ 📂view
 ┃ ┃ ┗ 📜app_test.dart
 ┣ 📂core
 ┃ ┣ 📂storage
 ┃ ┃ ┗ 📜app_storage_test.dart
 ┃ ┗ 📂theme
 ┃ ┃ ┗ 📜theme_controller_pod_test.dart
 ┣ 📂features
 ┃ ┣ 📂counter
 ┃ ┃ ┣ 📂pod
 ┃ ┃ ┃ ┗ 📜counter_pod_test.dart
 ┃ ┃ ┗ 📂view
 ┃ ┃ ┃ ┗ 📜counter_page_test.dart
 ┃ ┗ 📂theme_segment_btn
 ┃ ┃ ┗ 📂view
 ┃ ┃ ┃ ┗ 📜theme_segment_btn_test.dart
 ┣ 📂helpers
 ┃ ┣ 📜helpers.dart
 ┃ ┗ 📜pump_app.dart
 ┣ 📂shared
 ┃ ┣ 📂api_client
 ┃ ┃ ┗ 📂dio
 ┃ ┃ ┃ ┗ 📜dio_client_provider_test.dart
 ┃ ┣ 📂exception
 ┃ ┃ ┣ 📜base_exception_test.dart
 ┃ ┃ ┗ 📜exception_test.dart
 ┃ ┣ 📂pods
 ┃ ┃ ┣ 📜internet_checker_pod_test.dart
 ┃ ┃ ┗ 📜translations_pod_test.dart
 ┃ ┣ 📂riverpod_ext
 ┃ ┃ ┣ 📜asynvalue_easywhen_test.dart
 ┃ ┃ ┗ 📜cache_extension_test.dart
 ┃ ┗ 📂widgets
 ┃ ┃ ┣ 📜app_locale_popup_test.dart
 ┃ ┃ ┗ 📜no_interenet_widget_test.dart
 ┣ 📜init_test.dart
 ┗ 📜widget_test.dart
```
## 3. Layer Details

### 3.1. Presentation Layer

*   **Responsibility:**
    *   Rendering the user interface.
    *   Handling user interactions.
    *   Displaying data received from the Controller Layer.
    *   Navigation logic.
*   **Communication:**
    *   Receives state updates from the Controller Layer via Riverpod `Consumer`.
    *   Passes user actions (e.g., button clicks) to the Controller Layer.
*   **Implementation:**
    *   Stateless or stateful widgets for screens and UI components.
    *   Uses `Consumer` or `ConsumerWidget` to listen to providers.
    * Navigation using `AutoRoute`.
* **Example**
    ```dart
     class MyFeatureScreen extends ConsumerWidget{
       const MyFeatureScreen({super.key});
       @override
       Widget build(BuildContext context, WidgetRef ref){
          final featureState = ref.watch(featureControllerProvider);

          return Scaffold(
            appBar: AppBar(title: Text(featureState.title)),
            body: // ...
          );
        }
      }
    ```

### 3.2. Controller Layer

*   **Responsibility:**
    *   Contains business logic for a specific feature.
    *   Manages the state of the feature using Riverpod `StateNotifier`s.
    *   Retrieves data from the Data Layer.
    *   Updates the state and triggers UI updates.
    * Handles the `Result` from data layer.
*   **Communication:**
    *   Receives user input from the Presentation Layer.
    *   Requests data from the repository in the Data Layer.
    *   Provides state updates to the Presentation Layer.
    *   Uses `Auto Route` to navigate.
*   **Implementation:**
    *   Uses `StateNotifierProvider`, `FutureProvider`, `StreamProvider` as needed.
    *   Injects dependencies (e.g., repositories) using `ref.read` or `ref.watch`.
    *   Handles `Result` objects from the Data Layer, updating the UI state accordingly.
* **Example**
    ```dart
    final featureControllerProvider = StateNotifierProvider<FeatureController, FeatureState>((ref) {
        final featureRepository = ref.watch(featureRepositoryProvider);
        return FeatureController(featureRepository);
      });

      class FeatureController extends StateNotifier<FeatureState>{
        FeatureController(this._featureRepository) : super(const FeatureState());

        final FeatureRepository _featureRepository;

        Future<void> fetchData() async {
        //start loading state
          state = state.copyWith(isLoading: true);
          final result = await _featureRepository.fetchData();
          result.when(
          (data) {
            //handle success
            state = state.copyWith(data: data, isLoading: false);
          },
          (exception) {
            //handle error
             state = state.copyWith(error: exception.toString(), isLoading: false);
          },
        );
        }
      }

    ```
 * **Error handling**
      * return an error state to the UI, based on the Exception return by the result.

### 3.3. Data Layer

*   **Responsibility:**
    *   Provides data access for a specific feature.
    *   Abstracts data sources (local, remote, etc.).
    *   Defines data models.
    *   Transforms data if necessary.
    *   Returns `Result<Success, Exception>` objects.
*   **Sub-folders:**
    *   `repositories/`: Interfaces for data access.
    *   `data_sources/`: Implementations of data retrieval.
    *   `models/`: Data models used within the feature.
*   **Communication:**
    *   Receives data requests from the Controller Layer.
    *   Fetches data from data sources.
    *   Returns a `Result<Success, Exception>` to the Controller Layer.
* **Global Data vs Feature Data**
    * If the data is shared between features, it should be in the `shared/api_client` folder. If not it can be inside the `feature` data folder.
* **Example**
    ```dart
      // Feature Data
      final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
        final featureRemoteDataSource = ref.watch(featureRemoteDataSourceProvider);
        return FeatureRepositoryImpl(featureRemoteDataSource);
      });

      abstract class FeatureRepository {
        Future<Result<MyModel, Exception>> fetchData();
      }

      class FeatureRepositoryImpl implements FeatureRepository {
        FeatureRepositoryImpl(this._remoteDataSource);
        final FeatureRemoteDataSource _remoteDataSource;

        @override
        Future<Result<MyModel, Exception>> fetchData() {
          return _remoteDataSource.fetchData();
        }
      }

      final featureRemoteDataSourceProvider = Provider<FeatureRemoteDataSource>((ref) {
        final apiClient = ref.watch(apiClientProvider);
        return FeatureRemoteDataSourceImpl(apiClient);
      });

      abstract class FeatureRemoteDataSource {
        Future<Result<MyModel, Exception>> fetchData();
      }

      class FeatureRemoteDataSourceImpl implements FeatureRemoteDataSource {
        FeatureRemoteDataSourceImpl(this._apiClient);

        final ApiClient _apiClient;
        @override
        Future<Result<MyModel, Exception>> fetchData() async {
          try {
            final response = await _apiClient.get('/my-feature');
            final data = MyModel.fromJson(response.data);
            return Result.success(data);
          } catch (e) {
            return Result.failure(ServerException('Error fetching data: $e'));
          }
        }
      }

      // Result Class
      sealed class Result<T, E extends Exception> {
        const Result();

        factory Result.success(T data) = Success<T, E>;
        factory Result.failure(E exception) = Failure<T, E>;

        void when(
          void Function(T data) success,
          void Function(E exception) failure,
        ) {
          if (this is Success<T, E>) {
            success((this as Success<T, E>).data);
          } else if (this is Failure<T, E>) {
            failure((this as Failure<T, E>).exception);
          }
        }
      }

      class Success<T, E extends Exception> extends Result<T, E> {
        final T data;
        Success(this.data);
      }

      class Failure<T, E extends Exception> extends Result<T, E> {
        final E exception;
        Failure(this.exception);
      }

      //Example of Exception
      class ServerException implements Exception {
        final String message;
        ServerException(this.message);
      }
    ```

### 3.4. Core Layer

*   **Responsibility:**
    *   Provides foundational services used across the application.
    *   Examples: Local storage, routing, theming.
*   **Communication:**
    *   Used by other layers as needed.
*   **Implementation:**
    *   Singleton services.
    *   Utility classes.
* **Sub folders**
    * **local storage**
    * **router**
    * **theme**

### 3.5. Shared Layer

*   **Responsibility:**
    *   Houses services, utilities, and abstractions shared across multiple features.
*   **Sub-folders:**
    *   `api_client/`: API client, interceptors, error handlers.
    *   `exception/`: Base exceptions.
    * `extensions/`: custom extension.
    * `providers/` global providers.
    *   `riverpod_extensions/`: Custom Riverpod extensions.
    *   `widgets/`: Globally shared widgets.

### 3.6. Const Layer

* **Responsibility:**
    * Contains the const values used across the application.
* **Sub folders:**
    * `api_urls.dart`
    * `assets.dart`

## 4. State Management: Riverpod

*   **Why Riverpod?**
    *   Type-safe dependency injection.
    *   Testability.
    *   Composable state management.
*   **Provider Types:**
    *   `Provider`: For read-only values.
    *   `StateProvider`: For simple state.
    *   `StateNotifierProvider`: For complex state.
    *   `FutureProvider`: For asynchronous data.
    *   `StreamProvider`: For data streams.
*   **Placement:** Providers live within the Controller Layer.
* **How to use it?**
    * add examples

## 5. Navigation: Auto Route

*   **Type-Safe:** Ensures compile-time safety.
*   **Centralized:** Routes in `router.dart` and features route.
*   **Navigation:** Controllers use the router for navigation.
* **How to use it?**
    * add examples

## 6. Testing

*   **Types of Tests:**
    *   **Unit Tests:** Individual units (e.g., controller logic, repository logic).
    *   **Widget Tests:** UI components.
    *   **Integration Tests:** Multiple units or layers.
*   **Tools:**
    *   `riverpod_test`: Testing Riverpod providers.
    *   `mockito`: Mocking dependencies.
*   **Mocking:** Mock dependencies to isolate the code under test.
* **Example**
    ```dart
    // Example: Testing a FeatureController
    @GenerateMocks([FeatureRepository])
    void main() {
        late MockFeatureRepository mockFeatureRepository;
      late FeatureController sut;

      setUp(() {
        mockFeatureRepository = MockFeatureRepository();
        sut = FeatureController(mockFeatureRepository);
      });
      test('should return data on success', () async {
        // Arrange
        when(mockFeatureRepository.fetchData())
            .thenAnswer((_) async => Result.success(MyModel()));
        // Act
        await sut.fetchData();
        // Assert
        expect(sut.state.data != null, true);
        verify(mockFeatureRepository.fetchData()).called(1);
      });
    }
    ```

## 7. Localization: Slang

* **How to use it?**
    * add examples

## 8. Simplified Domain Logic

*   **No Dedicated Domain Layer:** Business logic lives in the Controller and Data layers.
*   **Benefits:** Reduces complexity.

## 9. Dependency Injection

*   **Riverpod's Role:** Riverpod provides dependency injection.
*   **Provider Scope:** Defines the scope of dependencies.
* **How to use it?**
    * add examples

## 10. Error Handling

*   **Layer-Specific:** Errors are handled using the `Result<Success, Exception>` type.
*   **Error Propagation:** Errors are propagated through the layers as a `Result.failure(Exception)`.
*   **Controller Handling:** The Controller layer uses the result `when()` to handle errors or success, and update the presentation layer.
* **How to use it?**
    * The `Result` class added in `3.3` can be used as an example.

## 11. Data Transformation

*   **When is Needed?**
    *   Data source returns a different model.
    *   Data needs adaptation.
*   **Where?**
    *   Inside the `repository` layer.
* **How to do it?**
    * add example

## 12. Code Generation

*   **Tools:**
    *   `auto_route_generator`: Generating routes.
    *   `build_runner`: Running code generation.
    *   `Slang`: for generating localization.
*   **Commands:**
    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```
*   **Benefits:**
    *   Reduced boilerplate.
    *   Type safety.
    *   Increased productivity.
* **How to use it?**
    * add examples

## 13. Communication Between Layers (Detailed)

This section now includes a diagram illustrating the typical data flow.

### 13.1. Layer Interaction Diagram
```txt
+-------------------+    +-------------------+    +-------------------+    +-----------------+
| Presentation      |--->| Controller        |--->| Data              |--->| External Source |
| (UI/Widgets)      |<---| (StateNotifier)   |<---| (Repository/DS)   |<---| (API/DB)        |
+-------------------+    +-------------------+    +-------------------+    +-----------------+
       ^                    |  Result.when()   ^                    |
       |                    |                  |                    |
(User Actions)       (State Updates)       (Result<T,E>)   (Data/Error)


```



**Explanation:**

1.  **User Actions:** The Presentation Layer handles user interactions (e.g., button presses, form submissions).
2.  **Controller Interaction:** User actions are passed to the Controller Layer.
3.  **Data Request:** The Controller requests data from the Data Layer (repository).
4. **Result:** The Data layer returns a `Result` object.
5.  **Data/Error:** The external source (API or DB) responds with data or an error.
6. **Result Handle:** The controller handles the result using `result.when()`.
7.  **State Updates:** The Controller updates its internal state (using `StateNotifier`).
8.  **UI Updates:** The Presentation Layer, listening to the controller's state changes, updates the UI accordingly.

### 13.2. Communication Details

*   **Presentation to Controller:**
    *   User interactions: Button clicks, form submissions, etc.
    *   Pass data to controller using controller's methods.
*   **Controller to Data/Global Data:**
    *   Controller requests data from repository.
    *   Asks for specific data or actions.
    *   Controller receives a `Result<Success, Exception>`.
*   **Data/Global Data to Controller:**
    *   Repository returns a `Result.success(data)` or `Result.failure(exception)`.
*   **Controller to Presentation:**
    *   Controller updates state via Riverpod.
    *   Presentation listens for changes via `Consumer`.
    * The controller uses `result.when` to update the presentation.
*   **Core to Other Layers:**
    *   Core services are injected as needed.
* **Navigation:**
     * Controller and other layers use auto_route to navigate.

### 13.3. Layer Relationship Diagram

```txt
+-----------------+
| Presentation    |
| (UI)            |
+-------+---------+
        | (Updates/Actions)
        v
+-------+---------+
| Controller      |
| (Business Logic)|
+-------+---------+
        | (Requests/Results)
        v
+-------+---------+
| Data            |
| (Repositories)  |
+-------+---------+
        | (Access)
        v
+-------+---------+
| External Source |
| (API, DB)       |
+-----------------+
        ^
        | (Core,Shared)
+-------+---------+
| Core & Shared   |
| (Services,Utils)|
+-----------------+
```


**Explanation**

*   **Presentation:** The top layer, responsible for what the user sees.
*   **Controller:** Handles business logic, state management, and orchestrates interactions between other layers.
*   **Data:** Manages data access (both local and remote).
*   **External Source:** Represents data sources like APIs or databases.
* **Core & Shared:** Contains core utilities and services, and shared elements that other layers can utilize.
* **Arrow:** represent the communication between layers.
* **(Updates/Actions):** the presentation layer receive update from controller and send user actions to it.
* **(Requests/Results):** The controller layer send requests to data layer and receive results.
* **(Access):** The data layer access the data from external source.
* **(Core, Shared):** The core & shared can be access by other layers.

## 14. Important Considerations

*   **Clear Separation of Concerns:** Maintain a strict separation between the Presentation, Controller, and Data layers. Avoid mixing UI logic with business logic or data access logic.
*   **Testing:** Write comprehensive tests for all layers. Unit tests are crucial for controllers and data layer components. Widget tests are important for the presentation layer. Consider integration tests for key workflows.
*   **Global vs. Feature-Specific Data:** Use global data in the `shared` folder sparingly. Prefer to keep data localized within features unless it is genuinely shared and core to the application.
*   **Dependency Injection:** Leverage Riverpod's dependency injection capabilities effectively. This improves testability and maintainability.
*   **Code Generation:** Use code generation tools to reduce boilerplate, improve type safety, and enhance productivity. However, understand the generated code.
*   **Explicit Error Handling:** The `Result<Success, Exception>` type is central to our error-handling strategy. Ensure it is used consistently throughout the Data and Controller layers. Consider how to handle different types of exceptions.
*   **Asynchronous Operations:** Be mindful of asynchronous operations when working with the Data and Controller layers. Use `FutureProvider`, `StreamProvider`, or `StateNotifier` effectively to manage asynchronous state updates.
*   **Data Transformation:** If the data retrieved from data sources needs to be transformed before being used in the Controller layer or the UI, the Data Layer (preferably the `repository`) is the place for it.
* **Keep It Simple:** If the domain logic is simple don't over engineer.
* **Review and Refactor:** Regularly review the architecture and refactor when needed. The architecture should evolve with the project.
* **Documentation:** Keep this architecture documentation updated and reflect changes that were made in the architecture.

## 15. Diagrams (Future Improvement)

*   **Detailed Sequence Diagrams:** For complex user flows, consider creating detailed sequence diagrams to show the interaction between layers.
* **Component Diagram:** A component diagram can be useful to visualize the different modules and how they interact with each other.
*   **Add More details to diagram:** The diagrams provided are a starting point. They can be expanded and improved.
