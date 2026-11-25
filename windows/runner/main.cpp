#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string_view>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kAppTitle[] = L"Meme Snatcher";

bool HasAffectedDisplayDriver() {
  // WER recorded repeated nvwgf2umx.dll crashes on this driver. Use Skia's
  // presentation path on matching systems and the engine default elsewhere.
  constexpr std::wstring_view kMachine = L"\\Registry\\Machine\\";
  constexpr std::wstring_view kNvidia = L"PCI\\VEN_10DE&";
  for (DWORD index = 0;; ++index) {
    DISPLAY_DEVICEW display{};
    display.cb = sizeof(display);
    if (!EnumDisplayDevicesW(nullptr, index, &display, 0)) return false;
    if (!(display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) ||
        _wcsnicmp(display.DeviceID, kNvidia.data(), kNvidia.size()) != 0 ||
        _wcsnicmp(display.DeviceKey, kMachine.data(), kMachine.size()) != 0) {
      continue;
    }
    wchar_t version[64]{};
    DWORD bytes = sizeof(version);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, display.DeviceKey + kMachine.size(),
                     L"DriverVersion", RRF_RT_REG_SZ, nullptr, version,
                     &bytes) == ERROR_SUCCESS &&
        std::wstring_view(version) == L"32.0.16.1088") {
      return true;
    }
  }
}

bool StartOrActivate(FlutterWindow& window) {
  const auto create = [&window]() {
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
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // OleInitialize also initializes this UI thread as an STA.  The shell's
  // IDataObject clipboard path used for original GIF/file copies requires OLE.
  const HRESULT ole_status = ::OleInitialize(nullptr);

  flutter::DartProject project(L"data");
  if (HasAffectedDisplayDriver()) {
    project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const bool started = StartOrActivate(window);
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
