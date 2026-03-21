#include <arpa/inet.h>
#include <curl/curl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <thread>

namespace {

std::string getenv_or(const char *key, const std::string &fallback) {
  const char *value = std::getenv(key);
  return value && *value ? value : fallback;
}

std::string random_hex(std::size_t bytes) {
  std::random_device rd;
  std::mt19937_64 gen(rd());
  std::uniform_int_distribution<uint32_t> dist(0, 255);

  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (std::size_t i = 0; i < bytes; ++i) {
    out << std::setw(2) << dist(gen);
  }
  return out.str();
}

std::string extract_header(const std::string &request, const std::string &header_name) {
  const std::string needle = header_name + ":";
  std::size_t pos = request.find(needle);
  if (pos == std::string::npos) {
    return "";
  }

  pos += needle.size();
  std::size_t end = request.find("\r\n", pos);
  if (end == std::string::npos) {
    return "";
  }

  while (pos < end && std::isspace(static_cast<unsigned char>(request[pos]))) {
    ++pos;
  }
  return request.substr(pos, end - pos);
}

struct TraceContext {
  std::string trace_id;
  std::string parent_span_id;
};

TraceContext parse_traceparent(const std::string &traceparent) {
  TraceContext ctx;
  std::stringstream ss(traceparent);
  std::string version;
  std::getline(ss, version, '-');
  std::getline(ss, ctx.trace_id, '-');
  std::getline(ss, ctx.parent_span_id, '-');
  return ctx;
}

std::string build_payload(const TraceContext &parent, const std::string &span_id,
                          std::uint64_t start_nanos, std::uint64_t end_nanos) {
  std::ostringstream body;
  body << "{"
       << "\"resourceSpans\":[{"
       << "\"resource\":{\"attributes\":["
       << "{\"key\":\"service.name\",\"value\":{\"stringValue\":\"cpp-service\"}},"
       << "{\"key\":\"service.version\",\"value\":{\"stringValue\":\"demo\"}}"
       << "]},"
       << "\"scopeSpans\":[{"
       << "\"scope\":{\"name\":\"cpp-service\"},"
       << "\"spans\":[{"
       << "\"traceId\":\"" << parent.trace_id << "\","
       << "\"spanId\":\"" << span_id << "\","
       << "\"parentSpanId\":\"" << parent.parent_span_id << "\","
       << "\"name\":\"cpp-handler\","
       << "\"kind\":\"SPAN_KIND_SERVER\","
       << "\"startTimeUnixNano\":\"" << start_nanos << "\","
       << "\"endTimeUnixNano\":\"" << end_nanos << "\","
       << "\"attributes\":["
       << "{\"key\":\"http.method\",\"value\":{\"stringValue\":\"GET\"}},"
       << "{\"key\":\"http.route\",\"value\":{\"stringValue\":\"/\"}}"
       << "],"
       << "\"status\":{\"code\":\"STATUS_CODE_OK\"}"
       << "}]"
       << "}]"
       << "}]"
       << "}";
  return body.str();
}

bool export_span(const std::string &payload) {
  CURL *curl = curl_easy_init();
  if (curl == nullptr) {
    return false;
  }

  struct curl_slist *headers = nullptr;
  headers = curl_slist_append(headers, "Content-Type: application/json");

  const std::string endpoint =
      getenv_or("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost:4318/v1/traces");

  curl_easy_setopt(curl, CURLOPT_URL, endpoint.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
  curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, payload.size());
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L);

  CURLcode result = curl_easy_perform(curl);

  curl_slist_free_all(headers);
  curl_easy_cleanup(curl);
  return result == CURLE_OK;
}

void handle_client(int client_fd) {
  char buffer[8192];
  std::memset(buffer, 0, sizeof(buffer));
  ssize_t bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
  if (bytes_read <= 0) {
    close(client_fd);
    return;
  }

  const std::string request(buffer, static_cast<std::size_t>(bytes_read));
  TraceContext parent = parse_traceparent(extract_header(request, "traceparent"));
  if (parent.trace_id.empty()) {
    parent.trace_id = random_hex(16);
  }
  if (parent.parent_span_id.empty()) {
    parent.parent_span_id = random_hex(8);
  }

  const std::string span_id = random_hex(8);
  const auto start = std::chrono::system_clock::now();

  std::this_thread::sleep_for(std::chrono::milliseconds(40));

  const auto end = std::chrono::system_clock::now();
  const auto start_nanos = std::chrono::duration_cast<std::chrono::nanoseconds>(
                               start.time_since_epoch())
                               .count();
  const auto end_nanos =
      std::chrono::duration_cast<std::chrono::nanoseconds>(end.time_since_epoch()).count();

  export_span(build_payload(parent, span_id, start_nanos, end_nanos));

  const std::string body = "cpp-service handled request OK";
  const std::string response =
      "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " +
      std::to_string(body.size()) + "\r\n\r\n" + body;
  send(client_fd, response.c_str(), response.size(), 0);
  close(client_fd);
}

}  // namespace

int main() {
  curl_global_init(CURL_GLOBAL_ALL);

  const int port = std::stoi(getenv_or("PORT", "8082"));
  const int server_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd < 0) {
    std::perror("socket");
    return 1;
  }

  int opt = 1;
  setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = INADDR_ANY;
  address.sin_port = htons(port);

  if (bind(server_fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) < 0) {
    std::perror("bind");
    close(server_fd);
    return 1;
  }

  if (listen(server_fd, 16) < 0) {
    std::perror("listen");
    close(server_fd);
    return 1;
  }

  std::cout << "cpp-service listening on :" << port << std::endl;
  while (true) {
    sockaddr_in client{};
    socklen_t client_len = sizeof(client);
    int client_fd = accept(server_fd, reinterpret_cast<sockaddr *>(&client), &client_len);
    if (client_fd < 0) {
      std::perror("accept");
      continue;
    }
    handle_client(client_fd);
  }

  close(server_fd);
  curl_global_cleanup();
  return 0;
}
