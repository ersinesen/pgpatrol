{pkgs}: {
  deps = [
    pkgs.postgresql
    pkgs.nettools
    pkgs.mkinitcpio-nfs-utils
    pkgs.jq
    pkgs.flutter
  ];
}
