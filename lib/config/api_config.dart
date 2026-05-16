// Set this to true when running locally (debug mode)
// const bool isLocalhost = bool.fromEnvironment('dart.vm.product') == false;
const bool isLocalhost = false;


// AUTO SWITCH
const String API_BASE_URL = isLocalhost
    ? "http://localhost:20626/api" // Only works on your PC
    : "https://malak-backend.onrender.com/api";

const String SOCKET_IO = isLocalhost
    ? "http://localhost:20626"
    : "https://malak-backend.onrender.com";

const String IMAGE_URL = isLocalhost
    ? "http://localhost:20626/"
    : "https://malak-backend.onrender.com/";

/// Fallback when /agora/config is unavailable; must match server AGORA_APP_ID
const String agoraAppIdFallback = '2b62436b11684c1aa0061759c55592e0';
