#ifndef RUNNER_GRAPHICS_COMPATIBILITY_H_
#define RUNNER_GRAPHICS_COMPATIBILITY_H_

#include <windows.h>

#include <string>

bool HasAffectedDisplayDriver();

// During D3D device creation, request Microsoft's software adapter for this
// executable path only. Existing DirectX Control Panel profiles belong to the
// user. We remove only the new volatile entry created by this instance.
class ScopedWarpProfile {
 public:
  explicit ScopedWarpProfile(bool enabled);
  ~ScopedWarpProfile();
  ScopedWarpProfile(const ScopedWarpProfile&) = delete;
  ScopedWarpProfile& operator=(const ScopedWarpProfile&) = delete;

 private:
  HKEY entry_ = nullptr;
  std::wstring key_name_;
};

#endif  // RUNNER_GRAPHICS_COMPATIBILITY_H_
