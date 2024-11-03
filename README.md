Sample app for using NGINX Unit with vibe.d.

To get started:  
- Install NGINX Unit: https://unit.nginx.org/installation/
- Run `dub build` (`dub build --debug=Concurrency` to test with delays added to request handling).
- Edit unit-config.json to replace "\<dub output directory\>" with your dub output directory.
- Start Unit with `unitd --no-daemon` if it hasn't been started automatically.
- Send the app config to Unit (the default control socket is in the docs for `--control` output by `unitd --help`):  
  ```shell
  sudo curl -X PUT --data-binary @unit-config.json --unix-socket <Unit control socket> http://localhost/config
  ```
- Restart Unit:  
  ```shell
  sudo curl -X GET --unix-socket <Unit control socket> http://localhost/control/applications/unit-vibed-hello-world/restart
  ```
- Test the app with: `curl -w @"curl-format.txt" -i http://127.0.0.1:8081`