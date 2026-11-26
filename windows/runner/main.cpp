#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <charconv>

#include "flutter_window.h"
#include "graphics_compatibility.h"
#include "utils.h"

namespace {
constexpr wchar_t kAppTitle[] = L"Meme Snatcher";

bool WaitForPreviousProcess(std::vector<std::string>& arguments) {
  if (arguments.empty() || arguments.front() != "--restart-after") return true;
  if (arguments.size() != 2) return false;
  const auto& argument = arguments[1];
  DWORD pid = 0;
  const auto parsed = std::from_chars(
      argument.data(), argument.data() + argument.size(), pid);
  if (parsed.ec != std::errc() || parsed.ptr != argument.data() + argument.size() ||
      pid == 0 || pid == GetCurrentProcessId()) {
    return false;
  }
  HANDLE previous = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (previous) {
    const DWORD wait = WaitForSingleObject(previous, 15000);
    CloseHandle(previous);
    if (wait != WAIT_OBJECT_0) return false;
  } else if (GetLastError() != ERROR_INVALID_PARAMETER) {
    return false;
  }
  arguments.clear();
  return true;
}

bool StartOrActivate(FlutterWindow& window, bool software_adapter) {
  const auto create = [&window, software_adapter]() {
    ScopedWarpProfile profile(software_adapter);
    return window.Create(kAppTitle, {10, 10}, {1280, 720});
  };
  if (IsHeadlessTestMode()) return create();

  // Hold the gate until the first HWND is ready, so simultaneous launches
  // cannot both miss it. Windows releases ownership if the starter crashes.
  HANDLE gate = CreateMutexW(nullptr, FALSE, L"Local\\JJHbrams.MemeSnatcher.Startup");
  if (!gate) return false;
  const DWORD wait = WaitForSingleObject(gate, 15000);
  const bool owns_gate = wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
  bool ok = false;
  if (owns_gate || wait == WAIT_TIMEOUT) {
    HWND existing = FindWindowW(Win32Window::kMainWindowClass, nullptr);
    const bool legacy = !existing;
    if (legacy) existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kAppTitle);
    if (existing) ok = TrayIcon::RequestRestore(existing, legacy);
    if (owns_gate && !ok && !IsWindow(existing)) ok = create();
  }
  if (owns_gate) ReleaseMutex(gate);
  CloseHandle(gate);
  return ok;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  auto command_line_arguments = GetCommandLineArguments();
  if (!WaitForPreviousProcess(command_line_arguments)) return EXIT_FAILURE;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // OleInitialize also initializes this UI thread as an STA.  The shell's
  // IDataObject clipboard path used for original GIF/file copies requires OLE.
  const HRESULT ole_status = ::OleInitialize(nullptr);

  flutter::DartProject project(L"data");
  const bool software_adapter = HasAffectedDisplayDriver();
  if (software_adapter) {
    project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const bool started = StartOrActivate(window, software_adapter);
  if (started && window.GetHandle()) {
    window.SetQuitOnClose(true);

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0) > 0) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }

  if (SUCCEEDED(ole_status)) {
    ::OleUninitialize();
  }
  return started ? EXIT_SUCCESS : EXIT_FAILURE;
}
