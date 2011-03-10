@api @api_environments @environments_cookbook_list
Feature: List cookbook versions for an environment via the REST API
  In order to know what cookbooks are available in a given environment
  As a developer
  I was to list all cookbooks versions for a given environment via the REST API

  Scenario Outline: List cookbook versions for an environment
    Given I am an administrator
      And I upload multiple versions of the 'version_test' cookbook
      And an 'environment' named 'skynet' exists
      And I am <user_type>
     When I 'GET' the path '/environments/skynet/cookbooks'
     Then the inflated responses key 'version_test' sub-key 'url' should match 'http://.+/cookbooks/version_test'
      And the inflated responses key 'version_test' sub-key 'versions' item '0' sub-key 'url' should match 'http://.+/cookbooks/version_test/(\d+.\d+.\d+)'
      And the inflated responses key 'version_test' sub-key 'versions' item '0' sub-key 'version' should equal '0.2.0'
      And the inflated responses key 'version_test' sub-key 'versions' should be '1' items long
     When I 'GET' the path '/environments/skynet/cookbooks?num_versions=2'
     Then the inflated responses key 'version_test' sub-key 'versions' should be '2' items long
      And the inflated responses key 'version_test' sub-key 'versions' item '0' sub-key 'version' should equal '0.2.0'
     When I 'GET' the path '/environments/skynet/cookbooks?num_versions=-1'
     Then the inflated responses key 'version_test' sub-key 'versions' should be '1' items long
     When I 'GET' the path '/environments/skynet/cookbooks?num_versions=invalid-input'
     Then the inflated responses key 'version_test' sub-key 'versions' should be '0' items long
     When I 'GET' the path '/environments/skynet/cookbooks?num_versions=all'
     Then the inflated responses key 'version_test' sub-key 'versions' should be '2' items long

    Examples:
      | user_type        |
      | an administrator |
      | a non-admin      |

  Scenario Outline: List cookbook versions for an environment should restrict only the specified cookbooks
    Given I am an administrator
      And I upload multiple versions of the 'version_test' cookbook
      And an 'environment' named '<env_name>' exists
     When I 'GET' the path '/environments/cookbooks_test/cookbooks'
      And the inflated responses key 'version_test' sub-key 'url' should match 'http://.+/cookbooks/version_test'
      And the inflated responses key 'version_test' sub-key 'versions' item '0' sub-key 'url' should match 'http://.+/cookbooks/version_test/<version_regexp>'

  Examples:
    | env_name        | version_regexp |
    | cookbooks-0.1.0 | 0.1.0          |
    | cookbooks-0.1.1 | 0.1.1          |
    | cookbooks-0.2.0 | 0.2.0          |

  Scenario: List cookbook versions for an environment with a wrong private key
    Given I am an administrator
      And an 'environment' named 'cookbooks-0.1.0' exists
     When I 'GET' the path '/environments/cookbooks_test/cookbooks' using a wrong private key
     Then I should get a '401 "Unauthorized"' exception
