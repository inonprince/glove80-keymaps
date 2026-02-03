{ config ? ./.
, firmware ? import ../src {}
}:
let
  keymap = "${config}/glove80.keymap";
  kconfig = "${config}/glove80.conf";
  glove80_left = firmware.zmk.override {
    board = "glove80_lh";
    keymap = keymap;
    kconfig = kconfig;
  };
  glove80_right = firmware.zmk.override {
    board = "glove80_rh";
    keymap = keymap;
    kconfig = kconfig;
  };
in
firmware.combine_uf2 glove80_left glove80_right
