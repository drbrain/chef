#
# Author:: Stephen Delano (<stephen@opscode.com>)
# Copyright:: Copyright (c) 2010 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'
require 'chef/environment'
require 'chef/json_compat'

class Chef
  class Knife
    class EnvironmentList < Knife

      banner "knife environment list (options)"

      option :with_uri,
        :short => "-w",
        :long => "--with-uri",
        :description => "Show corresponding URIs"

      def run
        output(format_list_for_display(Chef::Environment.list))
      end
    end
  end
end