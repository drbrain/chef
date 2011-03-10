#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Copyright:: Copyright (c) 2009-2011 Opscode, Inc.
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

require 'chef/mixin/xml_escape'
require 'chef/log'
require 'chef/config'
require 'chef/couchdb'
require 'chef/solr_query/solr_http_request'

class Chef
  class SolrQuery

    ID_KEY = "X_CHEF_id_CHEF_X"
    DEFAULT_PARAMS = Mash.new(:start => 0, :rows => 1000, :sort => "#{ID_KEY} asc", :wt => 'json', :indent => 'off').freeze
    FILTER_PARAM_MAP = {:database => 'X_CHEF_database_CHEF_X', :type => "X_CHEF_type_CHEF_X", :data_bag  => 'data_bag'}
    VALID_PARAMS = [:start,:rows,:sort,:q,:type]
    BUILTIN_SEARCH_TYPES = ["role","node","client","environment"]
    DATA_BAG_ITEM = 'data_bag_item'

    include Chef::Mixin::XMLEscape

    attr_accessor :query
    
    # Create a new Query object - takes the solr_url and optional
    # Chef::CouchDB object to inflate objects into.
    def initialize(couchdb = nil)
      @filter_query = {}

      if couchdb.nil?
        @database = Chef::Config[:couchdb_database]
        @couchdb = Chef::CouchDB.new(nil, Chef::Config[:couchdb_database])
      else
        unless couchdb.kind_of?(Chef::CouchDB)
          Chef::Log.warn("Passing the database name to Chef::Solr::Query initialization is deprecated. Please pass in the Chef::CouchDB object instead.")
          @database = couchdb
          @couchdb = Chef::CouchDB.new(nil, couchdb)
        else
          @database = couchdb.couchdb_database
          @couchdb = couchdb
        end
      end 
    end

    def filter_by(filter_query_params)
      filter_query_params.each do |key, value|
        @filter_query[FILTER_PARAM_MAP[key]] = value
      end
    end

    def filter_query
      @filter_query.map { |param, value| "+#{param}:#{value}" }.join(' ')
    end

    def filter_by_type(type)
      case type
      when *BUILTIN_SEARCH_TYPES
        filter_by(:type => type)
      else
        filter_by(:type => DATA_BAG_ITEM, :data_bag => type)
      end
    end

    def update_filter_query_from_params(params)
      filter_by(:database => @database)
      filter_by_type(params.delete(:type))
    end

    def update_query_from_params(params)
      original_query = params.delete(:q) || "*:*"
      @query = transform_search_query(original_query)
    end

    # Search Solr for objects of a given type, for a given query. If
    # you give it a block, it will handle the paging for you
    # dynamically.
    def search(params)
      params = VALID_PARAMS.inject({}) do |p, param_name|
        p[param_name] = params[param_name] if params.key?(param_name)
        p
      end
      update_filter_query_from_params(params)
      update_query_from_params(params)
      objects, start, total, response_header = execute_query(params)
      [ objects, start, total ]
    end

    # A raw query against CouchDB - takes the type of object to find, and raw
    # Solr options.
    #
    # You'll wind up having to page things yourself.
    def execute_query(options)
      results = solr_select(options)
      Chef::Log.debug("Bulk loading from #{@database}:\n#{results.inspect}") 
      objects = if results["response"]["docs"].length > 0
                  bulk_objects = @couchdb.bulk_get( results["response"]["docs"].collect { |d| d[ID_KEY] } )
                  Chef::Log.debug("bulk get of objects: #{bulk_objects.inspect}")
                  bulk_objects
                else
                  []
                end
      [ objects, results["response"]["start"], results["response"]["numFound"], results["responseHeader"] ] 
    end


    # Constants used for search query transformation
    FLD_SEP = "\001"
    SPC_SEP = "\002"
    QUO_SEP = "\003"
    QUO_KEY = "\004"

    def transform_search_query(q)
      return q if q == "*:*"

      # handled escaped quotes
      q = q.gsub(/\\"/, QUO_SEP)

      # handle quoted strings
      i = 1
      quotes = {}
      q = q.gsub(/([^ \\+()]+):"([^"]+)"/) do |m|
        key = QUO_KEY + i.to_s
        quotes[key] = "content#{FLD_SEP}\"#{$1}__=__#{$2}\""
        i += 1
        key
      end

      # a:[* TO *] => a*
      q = q.gsub(/\[\*[+ ]TO[+ ]\*\]/, '*')

      keyp = '[^ \\+()]+'
      lbrak = '[\[{]'
      rbrak = '[\]}]'

      # a:[blah TO zah] =>
      # content\001[a__=__blah\002TO\002a__=__zah]
      # includes the cases a:[* TO zah] and a:[blah TO *], but not
      # [* TO *]; that is caught above
      q = q.gsub(/(#{keyp}):(#{lbrak})([^\]}]+)[+ ]TO[+ ]([^\]}]+)(#{rbrak})/) do |m|
        if $3 == "*"
          "content#{FLD_SEP}#{$2}#{$1}__=__#{SPC_SEP}TO#{SPC_SEP}#{$1}__=__#{$4}#{$5}"
        elsif $4 == "*"
          "content#{FLD_SEP}#{$2}#{$1}__=__#{$3}#{SPC_SEP}TO#{SPC_SEP}#{$1}__=__\\ufff0#{$5}"
        else
          "content#{FLD_SEP}#{$2}#{$1}__=__#{$3}#{SPC_SEP}TO#{SPC_SEP}#{$1}__=__#{$4}#{$5}"
        end
      end

      # foo:bar => content:foo__=__bar
      q = q.gsub(/([^ \\+()]+):([^ +]+)/) { |m| "content:#{$1}__=__#{$2}" }

      # /002 => ' '
      q = q.gsub(/#{SPC_SEP}/, ' ')

      # replace quoted query chunks
      quotes.keys.each do |key|
        q = q.gsub(key, quotes[key])
      end

      # replace escaped quotes
      q = q.gsub(QUO_SEP, '\"')

      # /001 => ':'
      q = q.gsub(/#{FLD_SEP}/, ':')
      q
    end

    # TODO: dead code, only exercised by tests
    def select_url_from(params={})
      options = DEFAULT_PARAMS.merge(params)
      options[:fq] = filter_query
      options[:q] = @query
      "/solr/select?#{SolrHTTPRequest.url_join(options)}"
    end

    def to_hash(params={})
      options = DEFAULT_PARAMS.merge(params)
      options[:fq] = filter_query
      options[:q] = @query
      options
    end

    def solr_select(params={})
      SolrHTTPRequest.select(self.to_hash(params))
    end

    START_XML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".freeze
    START_DELETE_BY_QUERY = "<delete><query>".freeze
    END_DELETE_BY_QUERY = "</query></delete>\n".freeze
    COMMIT = "<commit/>\n".freeze

    def commit(opts={})
      SolrHTTPRequest.update("#{START_XML}#{COMMIT}")
    end

    def delete_database(db)
      query_data = xml_escape("X_CHEF_database_CHEF_X:#{db}")
      xml = "#{START_XML}#{START_DELETE_BY_QUERY}#{query_data}#{END_DELETE_BY_QUERY}"
      SolrHTTPRequest.update(xml)
      commit
    end

    def rebuild_index(db=Chef::Config[:couchdb_database])
      delete_database(db)

      results = {}
      [Chef::ApiClient, Chef::Node, Chef::Role].each do |klass|
        results[klass.name] = reindex_all(klass) ? "success" : "failed"
      end
      databags = Chef::DataBag.cdb_list(true)
      Chef::Log.info("Reloading #{databags.size.to_s} #{Chef::DataBag} objects into the indexer")
      databags.each { |i| i.add_to_index; i.list(true).each { |x| x.add_to_index } }
      results[Chef::DataBag.name] = "success"
      results
    end

    def reindex_all(klass, metadata={})
      begin
        items = klass.cdb_list(true)
        Chef::Log.info("Reloading #{items.size.to_s} #{klass.name} objects into the indexer")
        items.each { |i| i.add_to_index }
      rescue Net::HTTPServerException => e
        # 404s are okay, there might not be any of that kind of object...
        if e.message =~ /Not Found/
          Chef::Log.warn("Could not load #{klass.name} objects from couch for re-indexing (this is ok if you don't have any of these)")
          return false
        else
          raise e
        end
      rescue Exception => e
        Chef::Log.fatal("Chef encountered an error while attempting to load #{klass.name} objects back into the index")
        raise e
      end
      true
    end


  end
end
