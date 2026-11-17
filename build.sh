#!/bin/sh
# Tạo index.html độc lập từ game.html: dùng cho trang web (GitHub Pages) và cho app iPhone.
cd "$(dirname "$0")"
SITE="https://vunguyenitcontact.github.io/quy-dao/"
DESC="Chạm đúng lúc để phóng sao chổi qua từng hành tinh. Mỗi ngày một bản đồ mới, ai cũng chơi chung một bản đồ."
{ printf '<!doctype html>\n<html lang="vi">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">\n'
  printf '<meta name="theme-color" content="#08091f">\n'
  printf '<meta property="og:type" content="website">\n<meta property="og:site_name" content="Quỹ Đạo">\n<meta property="og:title" content="Quỹ Đạo: bạn qua được mấy hành tinh?">\n'
  printf '<meta property="og:description" content="%s">\n<meta property="og:url" content="%s">\n' "$DESC" "$SITE"
  printf '<meta property="og:image" content="%sog.png">\n<meta property="og:image:width" content="1200">\n<meta property="og:image:height" content="630">\n<meta name="twitter:card" content="summary_large_image">\n' "$SITE"
  printf '<link rel="icon" type="image/png" href="icon-192.png">\n<link rel="apple-touch-icon" href="icon-180.png">\n<link rel="manifest" href="manifest.webmanifest">\n'
  printf '<meta name="mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-capable" content="yes">\n<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n<meta name="apple-mobile-web-app-title" content="Quỹ Đạo">\n'
  sed -n '1,/^<\/style>$/p' game.html
  printf '</head>\n<body>\n'
  sed -n '/^<\/style>$/,$p' game.html | tail -n +2
  printf '</body>\n</html>\n'; } > index.html
# bản cho app iPhone
if [ -d ios/QuyDao/QuyDao ]; then cp index.html ios/QuyDao/QuyDao/index.html; fi
echo "built index.html"
