#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot script. Copy to ~/.termux/boot/start.sh and chmod +x.
termux-wake-lock
. $PREFIX/etc/profile   # starts termux-services (crond)
