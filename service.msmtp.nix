{

  agenix.secrets."msmtp-gmail-password" = ./secret.msmtp.gmail-password.age;

  programs.msmtp = {
    enable = true;
    accounts.default = {
      host = "smtp.gmail.com";
      port = 587;
      auth = true;
      tls_starttls = true;

      from = "blade30912@gmail.com";
      user = "blade30912@gmail.com";
      passwordeval = "${pkgs.coreutils}/bin/cat ${config.age.secrets."msmtp-gmail-password".path}";
    };
  };
}
