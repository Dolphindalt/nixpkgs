{ lib, pkgs, ... }:
{
  name = "lila";
  meta.maintainers = with lib.maintainers; [ dolphindalt ];

  nodes.machine =
    { config, ... }:
    {
      # MongoDB has unfree license (SSPL), but tests don't use external databases
      # We just test that the service configuration is correct
      services.lila = {
        enable = true;
        domain = "localhost";
        port = 9663;

        # Don't create local databases for this test to avoid unfree license issues
        # Just test that the service module works correctly
        database = {
          mongodb = {
            createLocally = false;
            uri = "mongodb://localhost:27017?appName=lila"; # Not actually used
          };
          redis = {
            createLocally = false;
            uri = "redis://localhost:6379"; # Not actually used
          };
        };

        # Use insecure default secrets for testing
        secrets = {
          bpassSecretFile = null; # Will use default insecure value
        };

        # Reduce memory for VM testing
        javaOptions = [
          "-Xmx2G"
          "-Xss4M"
          "-XX:MaxMetaspaceSize=512M"
        ];
      };

      # Increase VM memory for JVM
      virtualisation.memorySize = 3072;
    };

  testScript = ''
    # Start the machine
    machine.start()

    # Wait for lila service to be loaded (it will fail to fully start without databases)
    machine.wait_for_unit("multi-user.target")

    # Check that the lila service exists and was configured
    machine.succeed("systemctl cat lila.service")

    # Check that the user and group were created
    machine.succeed("id lila")
    machine.succeed("test -d /var/lib/lila")

    # Check that lila binary exists in the package
    machine.succeed("test -f ${pkgs.lila}/bin/lila")

    # Verify the service is configured with correct parameters
    machine.succeed("systemctl show lila.service | grep -q ExecStart")
    machine.succeed("systemctl show lila.service | grep -q 'User=lila'")
    machine.succeed("systemctl show lila.service | grep -q 'Group=lila'")
    machine.succeed("systemctl show lila.service | grep -q 'StateDirectory=lila'")
    machine.succeed("systemctl show lila.service | grep -q 'JAVA_HOME'")

    # Verify the lila package contains expected files
    machine.succeed("test -d ${pkgs.lila}/share/lila")
    machine.succeed("test -d ${pkgs.lila}/share/lila/conf.examples")

    print("Test passed: Lila service module is correctly configured")
    print("Note: Full integration test requires MongoDB (unfree license)")
  '';
}
