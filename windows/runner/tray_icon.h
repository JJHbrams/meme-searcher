#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

class TrayIcon {
 public:
  bool HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  bool active() const { return active_; }

 private:
  bool Add(HWND window);
  void Remove(HWND window);
  void Restore(HWND window);

  const UINT taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  bool active_ = false;
};

#endif  // RUNNER_TRAY_ICON_H_
