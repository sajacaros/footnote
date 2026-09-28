/// 빌드할 때 넣는 기본 동기화 서버 주소(선택).
///
///   flutter run --dart-define-from-file=config/app.json
///
/// 비워 두면 앱을 처음 열 때 로그인 화면에서 서버 주소를 입력받는다.
/// 사용자가 앱에서 바꾼 주소가 있으면 그쪽이 우선한다([ServerConfig]).
const defaultServerUrl = String.fromEnvironment('API_BASE_URL');
