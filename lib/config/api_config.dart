// Set this to true when running locally (debug mode)
const bool isLocalhost = bool.fromEnvironment('dart.vm.product') == false;
// const bool isLocalhost = false;


// AUTO SWITCH
const String API_BASE_URL = isLocalhost
    ? "http://10.0.2.2:20626/api" // Android emulator uses 10.0.2.2 for localhost
    : "https://malak-backend.onrender.com/api";

const String SOCKET_IO = isLocalhost
    ? "http://10.0.2.2:20626"
    : "https://malak-backend.onrender.com";

const String IMAGE_URL = isLocalhost
    ? "http://10.0.2.2:20626/"
    : "https://malak-backend.onrender.com/";
