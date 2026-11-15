#include "flutter_window.h"

#include <shobjidl.h>
#include <shellapi.h>
#include <wincodec.h>

#include <flutter/standard_method_codec.h>

#include <cstring>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kMediaActionsChannel[] =
    "dev.memesearcher.meme_searcher/media_actions";

struct ClipboardDropFiles {
  DWORD pFiles;
  POINT pt;
  BOOL fNC;
  BOOL fWide;
};

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return {};
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                      result.data(), size);
  return result;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& values,
                                         const char* key) {
  const auto found = values.find(flutter::EncodableValue(key));
  return found == values.end() ? nullptr : &found->second;
}

std::string StringArgument(const flutter::EncodableMap& values, const char* key) {
  const auto* value = FindValue(values, key);
  return value && std::holds_alternative<std::string>(*value)
             ? std::get<std::string>(*value)
             : std::string();
}

flutter::EncodableMap Success(const char* mode, const char* message) {
  return {{flutter::EncodableValue("mode"), flutter::EncodableValue(mode)},
          {flutter::EncodableValue("message"), flutter::EncodableValue(message)}};
}

HGLOBAL CreateDropFiles(const std::wstring& path) {
  const size_t byte_count = sizeof(ClipboardDropFiles) +
                            (path.size() + 2) * sizeof(wchar_t);
  auto handle = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, byte_count);
  if (!handle) {
    return nullptr;
  }
  auto* drop_files = static_cast<ClipboardDropFiles*>(GlobalLock(handle));
  if (!drop_files) {
    GlobalFree(handle);
    return nullptr;
  }
  drop_files->pFiles = sizeof(ClipboardDropFiles);
  drop_files->fWide = TRUE;
  auto* destination = reinterpret_cast<wchar_t*>(
      reinterpret_cast<BYTE*>(drop_files) + sizeof(ClipboardDropFiles));
  memcpy(destination, path.c_str(), path.size() * sizeof(wchar_t));
  GlobalUnlock(handle);
  return handle;
}

HGLOBAL CreateStaticImageDib(const std::wstring& path) {
  IWICImagingFactory* factory = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICFormatConverter* converter = nullptr;
  HGLOBAL result = nullptr;

  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) {
    status = factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ,
                                                WICDecodeMetadataCacheOnLoad,
                                                &decoder);
  }
  if (SUCCEEDED(status)) status = decoder->GetFrame(0, &frame);
  if (SUCCEEDED(status)) status = factory->CreateFormatConverter(&converter);
  if (SUCCEEDED(status)) {
    status = converter->Initialize(frame, GUID_WICPixelFormat32bppPBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0,
                                   WICBitmapPaletteTypeCustom);
  }
  UINT width = 0;
  UINT height = 0;
  if (SUCCEEDED(status)) status = converter->GetSize(&width, &height);
  const UINT stride = width * 4;
  const size_t pixel_bytes = static_cast<size_t>(stride) * height;
  if (SUCCEEDED(status) && width > 0 && height > 0 &&
      pixel_bytes <= MAXDWORD - sizeof(BITMAPINFOHEADER)) {
    result = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPINFOHEADER) + pixel_bytes);
    if (result) {
      auto* bits = static_cast<BYTE*>(GlobalLock(result));
      if (!bits) {
        GlobalFree(result);
        result = nullptr;
      } else {
        auto* header = reinterpret_cast<BITMAPINFOHEADER*>(bits);
        ZeroMemory(header, sizeof(*header));
        header->biSize = sizeof(*header);
        header->biWidth = static_cast<LONG>(width);
        header->biHeight = -static_cast<LONG>(height);
        header->biPlanes = 1;
        header->biBitCount = 32;
        header->biCompression = BI_RGB;
        status = converter->CopyPixels(nullptr, stride,
                                       static_cast<UINT>(pixel_bytes),
                                       bits + sizeof(BITMAPINFOHEADER));
        GlobalUnlock(result);
        if (FAILED(status)) {
          GlobalFree(result);
          result = nullptr;
        }
      }
    }
  }
  if (converter) converter->Release();
  if (frame) frame->Release();
  if (decoder) decoder->Release();
  if (factory) factory->Release();
  return result;
}

HGLOBAL CreateStaticImageDibFromPng(const std::vector<uint8_t>& png) {
  if (png.empty()) return nullptr;
  IWICImagingFactory* factory = nullptr;
  IWICStream* stream = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICFormatConverter* converter = nullptr;
  HGLOBAL result = nullptr;
  HRESULT status = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&factory));
  if (SUCCEEDED(status)) status = factory->CreateStream(&stream);
  if (SUCCEEDED(status)) {
    status = stream->InitializeFromMemory(const_cast<BYTE*>(png.data()),
                                          static_cast<DWORD>(png.size()));
  }
  if (SUCCEEDED(status)) {
    status = factory->CreateDecoderFromStream(stream, nullptr,
                                              WICDecodeMetadataCacheOnLoad,
                                              &decoder);
  }
  if (SUCCEEDED(status)) status = decoder->GetFrame(0, &frame);
  if (SUCCEEDED(status)) status = factory->CreateFormatConverter(&converter);
  if (SUCCEEDED(status)) {
    status = converter->Initialize(frame, GUID_WICPixelFormat32bppPBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0,
                                   WICBitmapPaletteTypeCustom);
  }
  UINT width = 0;
  UINT height = 0;
  if (SUCCEEDED(status)) status = converter->GetSize(&width, &height);
  const UINT stride = width * 4;
  const size_t pixel_bytes = static_cast<size_t>(stride) * height;
  if (SUCCEEDED(status) && width > 0 && height > 0 &&
      pixel_bytes <= MAXDWORD - sizeof(BITMAPINFOHEADER)) {
    result = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPINFOHEADER) + pixel_bytes);
    if (result) {
      auto* bits = static_cast<BYTE*>(GlobalLock(result));
      if (!bits) {
        GlobalFree(result);
        result = nullptr;
      } else {
        auto* header = reinterpret_cast<BITMAPINFOHEADER*>(bits);
        ZeroMemory(header, sizeof(*header));
        header->biSize = sizeof(*header);
        header->biWidth = static_cast<LONG>(width);
        header->biHeight = -static_cast<LONG>(height);
        header->biPlanes = 1;
        header->biBitCount = 32;
        header->biCompression = BI_RGB;
        status = converter->CopyPixels(nullptr, stride,
                                       static_cast<UINT>(pixel_bytes),
                                       bits + sizeof(BITMAPINFOHEADER));
        GlobalUnlock(result);
        if (FAILED(status)) {
          GlobalFree(result);
          result = nullptr;
        }
      }
    }
  }
  if (converter) converter->Release();
  if (frame) frame->Release();
  if (decoder) decoder->Release();
  if (stream) stream->Release();
  if (factory) factory->Release();
  return result;
}

const std::vector<uint8_t>* BytesArgument(const flutter::EncodableMap& values,
                                          const char* key) {
  const auto* value = FindValue(values, key);
  return value && std::holds_alternative<std::vector<uint8_t>>(*value)
             ? &std::get<std::vector<uint8_t>>(*value)
             : nullptr;
}

bool IsGifMimeType(const std::string& mime, const std::wstring& path) {
  if (_stricmp(mime.c_str(), "image/gif") == 0) return true;
  const auto extension = std::filesystem::path(path).extension().wstring();
  return _wcsicmp(extension.c_str(), L".gif") == 0;
}

bool IsHeadlessTestMode() {
  wchar_t value[8] = {};
  const DWORD length = GetEnvironmentVariableW(L"MEME_SEARCHER_HEADLESS_TEST",
                                                value, 8);
  return length == 1 && value[0] == L'1';
}

flutter::EncodableMap InspectClipboardForHeadlessTest() {
  flutter::EncodableMap details;
  if (!OpenClipboard(nullptr)) {
    details[flutter::EncodableValue("opened")] = flutter::EncodableValue(false);
    return details;
  }
  details[flutter::EncodableValue("opened")] = flutter::EncodableValue(true);
  details[flutter::EncodableValue("hasDib")] =
      flutter::EncodableValue(IsClipboardFormatAvailable(CF_DIB) != FALSE);
  const auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  const UINT count = drop ? DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) : 0;
  details[flutter::EncodableValue("hasFileDrop")] =
      flutter::EncodableValue(count > 0);
  if (count > 0) {
    const UINT length = DragQueryFileW(drop, 0, nullptr, 0);
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, 0, path.data(), static_cast<UINT>(path.size()));
    path.resize(length);
    const int utf8_length = WideCharToMultiByte(CP_UTF8, 0, path.data(),
                                                static_cast<int>(path.size()),
                                                nullptr, 0, nullptr, nullptr);
    std::string utf8(utf8_length, '\0');
    if (utf8_length > 0) {
      WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(path.size()),
                          utf8.data(), utf8_length, nullptr, nullptr);
    }
    details[flutter::EncodableValue("filePath")] = flutter::EncodableValue(utf8);
  }
  CloseClipboard();
  return details;
}

bool CopyToClipboard(const std::wstring& path, bool is_gif,
                     const std::vector<uint8_t>* fallback_png) {
  HGLOBAL files = CreateDropFiles(path);
  if (!files || !OpenClipboard(nullptr)) {
    if (files) GlobalFree(files);
    return false;
  }
  EmptyClipboard();
  if (!SetClipboardData(CF_HDROP, files)) {
    GlobalFree(files);
    CloseClipboard();
    return false;
  }
  if (!is_gif) {
    HGLOBAL dib = CreateStaticImageDib(path);
    if (!dib && fallback_png) dib = CreateStaticImageDibFromPng(*fallback_png);
    if (dib && !SetClipboardData(CF_DIB, dib)) {
      GlobalFree(dib);
    }
  }
  CloseClipboard();
  return true;
}

bool SaveWithPicker(const std::wstring& source, const std::wstring& suggested_name) {
  IFileSaveDialog* dialog = nullptr;
  IShellItem* item = nullptr;
  PWSTR destination = nullptr;
  bool saved = false;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&dialog)))) {
    return false;
  }
  dialog->SetFileName(suggested_name.c_str());
  if (SUCCEEDED(dialog->Show(nullptr)) && SUCCEEDED(dialog->GetResult(&item)) &&
      SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &destination))) {
    saved = CopyFileW(source.c_str(), destination, FALSE) != FALSE;
  }
  if (destination) CoTaskMemFree(destination);
  if (item) item->Release();
  dialog->Release();
  return saved;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  media_actions_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaActionsChannel,
          &flutter::StandardMethodCodec::GetInstance());
  media_actions_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "debugClipboardState") {
          if (!IsHeadlessTestMode()) {
            result->Error("test_only", "Clipboard inspection is available only to headless tests.");
            return;
          }
          result->Success(InspectClipboardForHeadlessTest());
          return;
        }
        const auto* arguments = call.arguments();
        if (!arguments || !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          result->Error("invalid_file", "The original file was not found.");
          return;
        }
        const auto& values = std::get<flutter::EncodableMap>(*arguments);
        const std::string path_arg = StringArgument(values, "path");
        const std::wstring path = Utf16FromUtf8(path_arg);
        if (path.empty() || !std::filesystem::is_regular_file(path)) {
          result->Error("invalid_file", "The original file was not found.");
          return;
        }
        if (call.method_name() == "copy") {
          if (!CopyToClipboard(path, IsGifMimeType(StringArgument(values, "mime"), path),
                               BytesArgument(values, "clipboardPng"))) {
            result->Error("clipboard_failed", "Could not copy the original file.");
            return;
          }
          result->Success(Success("clipboard", "Copied the original file."));
          return;
        }
        if (call.method_name() == "save") {
          const std::wstring name = Utf16FromUtf8(StringArgument(values, "name"));
          if (SaveWithPicker(path, name.empty() ? std::filesystem::path(path).filename().wstring() : name)) {
            result->Success(Success("save", "Saved the original file."));
          } else {
            result->Error("save_failed", "Could not save the original file.");
          }
          return;
        }
        if (call.method_name() == "share") {
          result->Error("unsupported", "Use copy or save on Windows.");
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!IsHeadlessTestMode()) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  media_actions_channel_.reset();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
