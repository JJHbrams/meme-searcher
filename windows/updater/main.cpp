#include <windows.h>
#include <winver.h>

#include <algorithm>
#include <cstdlib>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {
constexpr wchar_t kApp[] = L"meme_searcher.exe";
constexpr wchar_t kUpdater[] = L"meme_updater.exe";
constexpr wchar_t kNativeAssetsManifest[] = L"native_assets.json";

const std::vector<fs::path> kRuntimeFiles = {
    kApp, kUpdater, L"flutter_windows.dll",
    L"flutter_secure_storage_windows_plugin.dll", L"url_launcher_windows_plugin.dll",
    L"WebView2Loader.dll", L"webview_flutter_windows_plugin.dll",
    L"data/app.so", L"data/icudtl.dat"};

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), towlower);
  return value;
}

bool SamePath(const fs::path& a, const fs::path& b) {
  return Lower(fs::absolute(a).lexically_normal().wstring()) ==
         Lower(fs::absolute(b).lexically_normal().wstring());
}

bool IsReparsePoint(const fs::path& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

bool SafeDirectory(const fs::path& path) {
  std::error_code ec;
  return fs::is_directory(path, ec) && !ec && !IsReparsePoint(path);
}

void WriteError(const fs::path& stage, const std::wstring& message) {
  std::ofstream out(stage / L"error.txt", std::ios::binary | std::ios::trunc);
  if (!out) return;
  const int size = WideCharToMultiByte(CP_UTF8, 0, message.data(),
                                       static_cast<int>(message.size()), nullptr, 0,
                                       nullptr, nullptr);
  std::string utf8(size > 0 ? size : 0, '\0');
  if (size > 0) WideCharToMultiByte(CP_UTF8, 0, message.data(),
                                    static_cast<int>(message.size()), utf8.data(), size,
                                    nullptr, nullptr);
  out << utf8;
}

bool IsCancelled(const fs::path& stage) { return fs::exists(stage / L"cancelled"); }

bool IsAllowedPayloadFile(const fs::path& relative) {
  const auto normal = Lower(relative.generic_wstring());
  if (normal == kNativeAssetsManifest) return true;
  for (const auto& allowed : kRuntimeFiles) {
    if (normal == Lower(allowed.generic_wstring())) return true;
  }
  return normal.rfind(L"data/flutter_assets/", 0) == 0 ||
         normal.rfind(L"data/licenses/webview2/", 0) == 0;
}

bool ValidatePayload(const fs::path& stage, std::wstring* error) {
  const fs::path payload = stage / L"payload";
  if (!SafeDirectory(payload) || !SafeDirectory(payload / L"data") ||
      !SafeDirectory(payload / L"data/flutter_assets") ||
      !SafeDirectory(payload / L"data/licenses/webview2") || IsReparsePoint(stage)) {
    *error = L"업데이트 임시 폴더가 안전하지 않습니다.";
    return false;
  }
  for (const auto& required : kRuntimeFiles) {
    const fs::path source = payload / required;
    std::error_code exists_ec;
    if (!fs::is_regular_file(source, exists_ec) || exists_ec || IsReparsePoint(source)) {
      *error = L"업데이트 파일이 없거나 안전하지 않습니다: " + required.wstring();
      return false;
    }
  }
  std::error_code ec;
  for (fs::recursive_directory_iterator it(payload, fs::directory_options::skip_permission_denied, ec), end;
       !ec && it != end; it.increment(ec)) {
    const fs::path current = it->path();
    if (IsReparsePoint(current)) {
      *error = L"업데이트 패키지에 링크가 포함되어 있습니다.";
      return false;
    }
    if (it->is_regular_file(ec) && !IsAllowedPayloadFile(fs::relative(current, payload, ec))) {
      *error = L"업데이트 패키지에 허용되지 않은 파일이 포함되어 있습니다.";
      return false;
    }
  }
  if (ec) {
    *error = L"업데이트 패키지를 읽을 수 없습니다.";
    return false;
  }
  return true;
}

bool FileVersion(const fs::path& file, VS_FIXEDFILEINFO* version) {
  DWORD ignored = 0;
  const DWORD size = GetFileVersionInfoSizeW(file.c_str(), &ignored);
  if (size == 0) return false;
  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(file.c_str(), 0, size, data.data())) return false;
  VS_FIXEDFILEINFO* info = nullptr;
  UINT bytes = 0;
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &bytes) ||
      !info || bytes < sizeof(*info) || info->dwSignature != 0xfeef04bd) return false;
  *version = *info;
  return true;
}

bool NewerVersion(const fs::path& candidate, const fs::path& running) {
  VS_FIXEDFILEINFO next = {}, current = {};
  if (!FileVersion(candidate, &next) || !FileVersion(running, &current)) return false;
  const ULONGLONG a = (static_cast<ULONGLONG>(next.dwFileVersionMS) << 32) | next.dwFileVersionLS;
  const ULONGLONG b = (static_cast<ULONGLONG>(current.dwFileVersionMS) << 32) | current.dwFileVersionLS;
  return a > b;
}

bool MoveEntry(const fs::path& source, const fs::path& target) {
  std::error_code ec;
  fs::create_directories(target.parent_path(), ec);
  return !ec &&
         MoveFileExW(source.c_str(), target.c_str(), MOVEFILE_WRITE_THROUGH);
}

bool Start(const fs::path& exe, PROCESS_INFORMATION* process) {
  STARTUPINFOW startup = {sizeof(startup)};
  PROCESS_INFORMATION created = {};
  std::wstring command = L"\"" + exe.wstring() + L"\"";
  const bool started = CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                                      0, nullptr, exe.parent_path().c_str(), &startup, &created) != FALSE;
  if (started && process) *process = created;
  else if (started) { CloseHandle(created.hThread); CloseHandle(created.hProcess); }
  return started;
}

void ReportFailure(const fs::path& stage, const std::wstring& message) {
  WriteError(stage, message);
  wchar_t headless[2] = {};
  if (GetEnvironmentVariableW(L"MEME_SEARCHER_HEADLESS_TEST", headless, 2) == 1 &&
      headless[0] == L'1') return;
  MessageBoxW(nullptr, message.c_str(), L"Meme Snatcher", MB_OK | MB_ICONWARNING);
}

bool Restore(const fs::path& install, const fs::path& payload,
             const fs::path& backup, const std::vector<fs::path>& installed,
             const std::vector<fs::path>& backed_up) {
  bool restored = true;
  for (auto it = installed.rbegin(); it != installed.rend(); ++it) {
    if (!MoveEntry(install / *it, payload / *it)) restored = false;
  }
  for (auto it = backed_up.rbegin(); it != backed_up.rend(); ++it) {
    if (!MoveEntry(backup / *it, install / *it)) restored = false;
  }
  return restored;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  const int argc = __argc;
  wchar_t** argv = __wargv;
  if (argc != 3) return 2;
  wchar_t* end = nullptr;
  const DWORD parent_pid = wcstoul(argv[1], &end, 10);
  if (!parent_pid || !end || *end) return 2;
  const fs::path stage = fs::absolute(argv[2]).lexically_normal();
  const fs::path install = stage.parent_path();
  wchar_t self_buffer[MAX_PATH] = {};
  if (!GetModuleFileNameW(nullptr, self_buffer, MAX_PATH) ||
      !SamePath(self_buffer, stage / kUpdater) ||
      stage.filename().wstring().rfind(L".meme-update-", 0) != 0 || !SafeDirectory(stage) ||
      !SafeDirectory(install) || IsReparsePoint(install)) return 3;

  HANDLE parent = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent_pid);
  if (!parent) { WriteError(stage, L"실행 중인 앱 프로세스를 확인할 수 없습니다."); return 4; }
  wchar_t image[MAX_PATH] = {};
  DWORD image_size = MAX_PATH;
  const bool trusted_parent = QueryFullProcessImageNameW(parent, 0, image, &image_size) &&
      SamePath(image, install / kApp);
  if (!trusted_parent) {
    WriteError(stage, L"실행 중인 앱과 설치 폴더의 실행 파일이 다릅니다. 앱을 다시 시작해 주세요.");
    CloseHandle(parent); return 5;
  }
  if (!NewerVersion(stage / L"payload" / kApp, install / kApp)) {
    WriteError(stage, L"업데이트 파일이 설치 폴더의 앱보다 새 버전인지 확인할 수 없습니다.");
    CloseHandle(parent); return 5;
  }
  std::wstring error;
  if (!ValidatePayload(stage, &error) || IsCancelled(stage)) {
    WriteError(stage, error.empty() ? L"업데이트가 취소되었습니다." : error);
    CloseHandle(parent); return 6;
  }
  // Check every existing destination ancestor before telling Dart it is safe to
  // exit. The transaction must never traverse a junction after the app exits.
  std::error_code preflight_ec;
  const fs::path install_data = install / L"data";
  const fs::path install_licenses = install_data / L"licenses";
  if ((fs::exists(install_data, preflight_ec) && !SafeDirectory(install_data)) || preflight_ec ||
      (fs::exists(install_licenses, preflight_ec) && !SafeDirectory(install_licenses)) || preflight_ec) {
    WriteError(stage, L"기존 데이터 폴더가 안전하지 않습니다.");
    CloseHandle(parent); return 6;
  }
  const fs::path payload = stage / L"payload";
  std::error_code ec;
  const bool has_native_assets = fs::exists(payload / kNativeAssetsManifest, ec);
  if (ec) {
    WriteError(stage, L"업데이트의 네이티브 에셋 정보를 확인할 수 없습니다.");
    CloseHandle(parent);
    return 8;
  }
  const fs::path backup = stage / L"backup";
  if (!fs::create_directory(backup, ec) || ec) {
    WriteError(stage, L"업데이트 백업 폴더를 만들 수 없습니다.");
    CloseHandle(parent);
    return 8;
  }
  {
    std::ofstream marker(stage / L"ready", std::ios::binary | std::ios::trunc);
    if (!(marker << "ready\n" << std::flush)) {
      CloseHandle(parent);
      return 8;
    }
  }
  for (;;) {
    const DWORD result = WaitForSingleObject(parent, 250);
    if (IsCancelled(stage)) { CloseHandle(parent); return 0; }
    if (result == WAIT_OBJECT_0) break;
    if (result != WAIT_TIMEOUT) { WriteError(stage, L"앱 종료를 기다리지 못했습니다."); CloseHandle(parent); return 7; }
  }
  CloseHandle(parent);
  if (IsCancelled(stage)) return 0;

  std::vector<fs::path> owned = kRuntimeFiles;
  if (has_native_assets) owned.emplace_back(kNativeAssetsManifest);
  owned.push_back(L"data/flutter_assets");
  owned.push_back(L"data/licenses/webview2");
  std::vector<fs::path> backed_up;
  std::vector<fs::path> installed;
  bool applied = true;
  for (const auto& relative : owned) {
    const fs::path destination = install / relative;
    if (fs::exists(destination, ec)) {
      if (IsReparsePoint(destination) ||
          !MoveEntry(destination, backup / relative)) {
        applied = false;
        break;
      }
      backed_up.push_back(relative);
    }
    if (ec) {
      applied = false;
      break;
    }
  }
  if (applied) {
    // The runner heads the backup order and comes last in the install order.
    std::rotate(owned.begin(), owned.begin() + 1, owned.end());
    for (const auto& relative : owned) {
      if (!MoveEntry(payload / relative, install / relative)) {
        applied = false;
        break;
      }
      installed.push_back(relative);
    }
  }

  PROCESS_INFORMATION updated = {};
  if (applied && Start(install / kApp, &updated)) {
    CloseHandle(updated.hThread);
    const DWORD started = WaitForSingleObject(updated.hProcess, 5000);
    CloseHandle(updated.hProcess);
    if (started == WAIT_TIMEOUT) {
      fs::remove_all(backup, ec);
      if (!ec) fs::remove_all(payload, ec);
      if (!ec) std::ofstream(stage / L"done", std::ios::binary) << "done\n";
      return 0;
    }
  }

  if (!Restore(install, payload, backup, installed, backed_up)) {
    ReportFailure(stage, L"이전 버전 복원이 완료되지 않았어요. 백업 위치\n" +
                         backup.wstring());
    return 9;
  }
  fs::remove_all(backup, ec);
  fs::remove_all(payload, ec);
  const bool reopened = Start(install / kApp, nullptr);
  ReportFailure(stage, reopened
      ? L"업데이트에 실패해 이전 버전을 복원하고 다시 열었어요."
      : L"업데이트에 실패해 이전 버전을 복원했어요. 앱을 다시 열어 주세요.");
  return 10;
}
