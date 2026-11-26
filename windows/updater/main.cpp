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

bool CopyFileReplacing(const fs::path& source, const fs::path& target) {
  std::error_code ec;
  fs::create_directories(target.parent_path(), ec);
  return !ec && CopyFileW(source.c_str(), target.c_str(), FALSE) != FALSE;
}

void RemoveOwnedTree(const fs::path& root, const fs::path& relative) {
  std::error_code ec;
  fs::remove_all(root / relative, ec);
}

bool CopyTree(const fs::path& source, const fs::path& target) {
  std::error_code ec;
  fs::create_directories(target, ec);
  if (ec) return false;
  for (fs::recursive_directory_iterator it(source, fs::directory_options::skip_permission_denied, ec), end;
       !ec && it != end; it.increment(ec)) {
    const fs::path relative = fs::relative(it->path(), source, ec);
    if (ec) break;
    if (it->is_directory(ec)) fs::create_directories(target / relative, ec);
    else if (it->is_regular_file(ec) && !CopyFileReplacing(it->path(), target / relative)) return false;
    if (ec) break;
  }
  return !ec;
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
  if (!trusted_parent || !NewerVersion(stage / L"payload" / kApp, install / kApp)) {
    WriteError(stage, L"업데이트 대상 앱 또는 버전을 확인할 수 없습니다.");
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
  { std::ofstream(stage / L"ready", std::ios::binary | std::ios::trunc) << "ready\n"; }
  for (;;) {
    const DWORD result = WaitForSingleObject(parent, 250);
    if (IsCancelled(stage)) { CloseHandle(parent); return 0; }
    if (result == WAIT_OBJECT_0) break;
    if (result != WAIT_TIMEOUT) { WriteError(stage, L"앱 종료를 기다리지 못했습니다."); CloseHandle(parent); return 7; }
  }
  CloseHandle(parent);
  if (IsCancelled(stage)) return 0;

  const fs::path payload = stage / L"payload";
  std::error_code ec;
  const fs::path backup = stage / L"backup";
  if (fs::exists(backup, ec) || ec || !fs::create_directory(backup, ec) || ec) {
    WriteError(stage, L"업데이트 백업 폴더를 만들 수 없습니다."); return 8;
  }
  std::vector<fs::path> owned = kRuntimeFiles;
  owned.push_back(L"data/flutter_assets");
  owned.push_back(L"data/licenses/webview2");
  std::vector<fs::path> moved;
  std::vector<fs::path> copied_files;
  bool copied_assets = false;
  bool copied_licenses = false;
  bool applied = true;
  for (const auto& relative : owned) {
    const fs::path destination = install / relative;
    if (fs::exists(destination, ec)) {
      if (IsReparsePoint(destination)) { applied = false; break; }
      fs::create_directories((backup / relative).parent_path(), ec);
      if (ec || !MoveFileExW(destination.c_str(), (backup / relative).c_str(), MOVEFILE_WRITE_THROUGH)) { applied = false; break; }
      moved.push_back(relative);
    }
    if (ec) { applied = false; break; }
  }
  if (applied) {
    // Install the launcher last. Until its dependencies are in place, a user
    // clicking the old launcher sees it absent rather than a half-updated app.
    for (const auto& relative : kRuntimeFiles) {
      if (relative == fs::path(kApp)) continue;
      copied_files.push_back(relative);
      if (!CopyFileReplacing(payload / relative, install / relative)) { applied = false; break; }
    }
    if (applied) { copied_assets = true; applied = CopyTree(payload / L"data/flutter_assets", install / L"data/flutter_assets"); }
    if (applied) { copied_licenses = true; applied = CopyTree(payload / L"data/licenses/webview2", install / L"data/licenses/webview2"); }
    if (applied) { copied_files.push_back(kApp); if (!CopyFileReplacing(payload / kApp, install / kApp)) applied = false; }
  }
  if (!applied) {
    // Never touch an entry that was not moved or copied by this transaction.
    for (const auto& relative : copied_files) RemoveOwnedTree(install, relative);
    if (copied_assets) RemoveOwnedTree(install, L"data/flutter_assets");
    if (copied_licenses) RemoveOwnedTree(install, L"data/licenses/webview2");
    bool restored = true;
    for (auto it = moved.rbegin(); it != moved.rend(); ++it) {
      fs::create_directories((install / *it).parent_path(), ec);
      if (ec || !MoveFileExW((backup / *it).c_str(), (install / *it).c_str(), MOVEFILE_WRITE_THROUGH)) restored = false;
    }
    if (!restored) {
      WriteError(stage, L"업데이트 적용에 실패했고 이전 버전 복원도 완료되지 않았습니다. 지원팀에 error.txt를 보내주세요.");
      return 9;
    }
    fs::remove_all(backup, ec);
    PROCESS_INFORMATION restored_process = {};
    Start(install / kApp, &restored_process);
    if (restored_process.hThread) CloseHandle(restored_process.hThread);
    if (restored_process.hProcess) CloseHandle(restored_process.hProcess);
    WriteError(stage, L"업데이트 적용에 실패해 이전 버전으로 복원했습니다.");
    fs::remove_all(payload, ec);
    return 9;
  }
  PROCESS_INFORMATION updated = {};
  if (!Start(install / kApp, &updated)) {
    for (const auto& relative : copied_files) RemoveOwnedTree(install, relative);
    if (copied_assets) RemoveOwnedTree(install, L"data/flutter_assets");
    if (copied_licenses) RemoveOwnedTree(install, L"data/licenses/webview2");
    bool restored = true;
    for (auto it = moved.rbegin(); it != moved.rend(); ++it) {
      fs::create_directories((install / *it).parent_path(), ec);
      if (ec || !MoveFileExW((backup / *it).c_str(), (install / *it).c_str(), MOVEFILE_WRITE_THROUGH)) restored = false;
    }
    if (!restored) { WriteError(stage, L"앱을 다시 시작하지 못했고 이전 버전 복원도 완료되지 않았습니다."); return 10; }
    fs::remove_all(backup, ec);
    PROCESS_INFORMATION restored_process = {};
    Start(install / kApp, &restored_process);
    if (restored_process.hThread) CloseHandle(restored_process.hThread);
    if (restored_process.hProcess) CloseHandle(restored_process.hProcess);
    WriteError(stage, L"업데이트된 앱을 시작하지 못해 이전 버전으로 복원했습니다.");
    fs::remove_all(payload, ec);
    return 10;
  }
  CloseHandle(updated.hThread);
  // A process that exits immediately is an update failure; restore only files
  // this transaction moved, and retain the backup if restoration is incomplete.
  if (WaitForSingleObject(updated.hProcess, 5000) == WAIT_OBJECT_0) {
    CloseHandle(updated.hProcess);
    for (const auto& relative : copied_files) RemoveOwnedTree(install, relative);
    if (copied_assets) RemoveOwnedTree(install, L"data/flutter_assets");
    if (copied_licenses) RemoveOwnedTree(install, L"data/licenses/webview2");
    bool restored = true;
    for (auto it = moved.rbegin(); it != moved.rend(); ++it) {
      fs::create_directories((install / *it).parent_path(), ec);
      if (ec || !MoveFileExW((backup / *it).c_str(), (install / *it).c_str(), MOVEFILE_WRITE_THROUGH)) restored = false;
    }
    if (!restored) { WriteError(stage, L"새 버전이 시작되지 않았고 이전 버전 복원도 완료되지 않았습니다."); return 11; }
    fs::remove_all(backup, ec);
    PROCESS_INFORMATION restored_process = {};
    Start(install / kApp, &restored_process);
    if (restored_process.hThread) CloseHandle(restored_process.hThread);
    if (restored_process.hProcess) CloseHandle(restored_process.hProcess);
    WriteError(stage, L"새 버전이 시작되지 않아 이전 버전으로 복원했습니다.");
    fs::remove_all(payload, ec);
    return 11;
  }
  CloseHandle(updated.hProcess);
  fs::remove_all(backup, ec);
  fs::remove_all(payload, ec);
  std::ofstream(stage / L"done", std::ios::binary | std::ios::trunc) << "done\n";
  // Leave only our staged executable plus ready/done. It cannot delete itself;
  // Dart may delete exactly those known names on the next app start.
  return 0;
}
