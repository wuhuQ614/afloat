#include "flutter_window.h"

#include <optional>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  // Register clipboard image read channel
  auto clipboard_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.smartenglish/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getImage") {
          if (!OpenClipboard(nullptr)) {
            result->Error("clipboard_error", "Failed to open clipboard");
            return;
          }
          HANDLE hData = GetClipboardData(CF_DIB);
          if (hData == nullptr) {
            CloseClipboard();
            result->Success(flutter::EncodableValue(std::vector<uint8_t>{}));
            return;
          }
          auto* dib = static_cast<BITMAPINFOHEADER*>(GlobalLock(hData));
          if (dib == nullptr) {
            CloseClipboard();
            result->Success(flutter::EncodableValue(std::vector<uint8_t>{}));
            return;
          }
          int width = dib->biWidth;
          int height = abs(dib->biHeight);
          int bpp = dib->biBitCount;
          int row_size = ((width * bpp + 31) / 32) * 4;
          int pixel_data_size = row_size * height;
          uint8_t* pixels = reinterpret_cast<uint8_t*>(dib) + dib->biSize;

          BITMAPFILEHEADER bfh = {};
          bfh.bfType = 0x4D42;
          bfh.bfOffBits = sizeof(BITMAPFILEHEADER) + dib->biSize;
          bfh.bfSize = bfh.bfOffBits + pixel_data_size;

          std::vector<uint8_t> bmp_data;
          bmp_data.resize(bfh.bfSize);
          memcpy(bmp_data.data(), &bfh, sizeof(BITMAPFILEHEADER));
          memcpy(bmp_data.data() + sizeof(BITMAPFILEHEADER), dib, dib->biSize);
          memcpy(bmp_data.data() + bfh.bfOffBits, pixels, pixel_data_size);

          GlobalUnlock(hData);
          CloseClipboard();

          result->Success(flutter::EncodableValue(bmp_data));
        } else {
          result->NotImplemented();
        }
      });

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
