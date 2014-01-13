require "focuslight"
require "digest"

module Focuslight
  class Graph
    def self.concrete(row)
      if row.has_key?('mode') && row.has_key?('type')
        Focuslight::SimpleGraph.new(row)
      else
        Focuslight::ComplexGraph.new(row)
      end
    end

    attr_accessor :id, :service, :section, :graph, :number, :description, :sort
    attr_accessor :meta
    attr_accessor :created_at_time, :updated_at_time

    attr_accessor :c_type, :c_gmode, :stack # for complex graph construction

    def initialize(row)
      @row_hash = row

      @id = row['id']
      @service = row['service_name']
      @section = row['section_name']
      @graph = row['graph_name']
      @number = row['number'].to_i # NOT NULL DEFAULT 0
      @description = row['description'] || ''
      @sort = row['sort'].to_i # NOT NULL DEFAULT 0

      @meta = row['meta']
      @parsed_meta = JSON.parse(@meta || '{}')

      @created_at_time = Time.at(row['created_at'].to_i)
      @updated_at_time = Time.at(row['updated_at'].to_i)
    end

    def created_at
      @created_at_time.strftime('%Y/%m/%d %T')
    end

    def updated_at
      @updated_at_time.strftime('%Y/%m/%d %T')
    end

    def to_hash
      {
        id: @id, service_name: @service, section_name: @section, graph_name: @graph,
        number: @number, description: @description, sort: @sort, meta: @meta,
        created_at: self.created_at(), updated_at: self.updated_at(),
      }
    end
  end

  class SimpleGraph < Graph
    COLUMNS = %w(service_name section_name graph_name number mode color llimit sllimit created_at updated_at)
    PLACEHOLDERS = COLUMNS.map{|c| '?'}

    attr_accessor :mode, :gmode, :color, :ulimit, :llimit, :sulimit, :sllimit, :type, :stype

    attr_reader :md5
    attr_accessor :adjust, :adjustval, :unit
    attr_accessor :subtract, :subtract_short

    def initialize(row)
      super

      @mode = row['mode'] || 'gauge' # NOT NULL DEFAULT 'gauge'
      @gmode = row['gmode'] || 'gauge'
      @color = row['color'] || '#00CC00' # NOT NULL DEFAULT '#00CC00'
      @ulimit = row['ulimit'] || 1000000000000000 # NOT NULL DEFAULT 1000000000000000
      @llimit = row['llimit'] || 0
      @sulimit = row['sulimit'] || 100000
      @sllimit = row['sllimit'] || 0
      @type = row['type'] || 'AREA'
      @stype = row['stype'] || 'AREA'

      @md5 = Digest::MD5.hex_digest(@id.to_s)

      @adjust = @parsed_meta.fetch('adjust', '*')
      @adjustval = @parsed_meta.fetch('adjustval', '1')
      @unit = @parsed_meta.fetch('unit', '')
    end

    def to_hash
      simple = {
        mode: @mode, gmode: @gmode, color: @color,
        ulimit: @ulimit, llimit: @llimit, sulimit: @sulimit, sllimit: @sllimit,
        type: @type, stype: @stype, md5: @md5,
        adjust: @adjust, adjustval: @adjustval, unit: @unit
      }
      hash = super
      hash.merge(simple)
    end

    def complex?
      false
    end

    def update(args={})
      meta = @parsed_meta.dup
      args.each do |k, v|
        case k
        when 'number' then @number = v
        when 'description' then @description = v
        when 'sort' then @sort = v
        when 'mode' then @mode = v
        when 'gmode' then @gmode = v
        when 'color' then @color = v
        when 'ulimit' then @ulimit = v
        when 'llimit' then @llimit = v
        when 'sulimit' then @sulimit = v
        when 'sllimit' then @sllimit = v
        when 'type' then @type = v
        when 'stype' then @stype = v
        else
          meta[k] = v
        end
      end
      @parsed_meta = self.class.meta_clean(@parsed_meta.merge(meta))
      @meta = JSON.stringify(@parsed_meta)
    end

    def self.meta_clean(args={})
      args.delete_if do |k,v|
        %w(id service_name section_name graph_name number
           description sort mode gmode color ulimit llimit sulimit sllimit type stype).include?(k.to_s)
      end
    end
  end

  class ComplexGraph
    attr_accessor :sumup, :data_rows
    attr_reader :complex_graph

    def initialize(row)
      super

      uri = ['type-1', 'path-1', 'gmode-1'].map{|k| @parsed_meta[k]}.join(':') + ':0' # stack

      data_rows = []

      first_row = {
        type: @parsed_meta['type-1'],
        path: @parsed_meta['path-1'],
        gmode: @parsed_meta['gmode-1'],
        stack: false,
        graphid: @parsed_meta['path-1'],
      }
      data_rows << first_row

      unless @parsed_meta['type-2'].is_a?(Array)
        ['type-2', 'path-2', 'gmode-2', 'stack-2'].each do |key|
          @parsed_meta[key] = [@parsed_meta[key]].flatten
        end
      end

      @parsed_meta['type-2'].each_with_index do |type, i|
        t = @parsed_meta['type-2'][i]
        p = @parsed_meta['path-2'][i] # id?
        g = @parsed_meta['gmode-2'][i]
        s = @parsed_meta['stack-2'][i]
        uri += ':' + [t, p, g, s].join(':')
        data_rows << {type: t, path: p, gmode: g, stack: s, graphid: p}
      end

      @sumup = @parsed_meta.fetch('sump', 0)
      @data_rows = data_rows
      @complex_graph = uri
    end

    def to_hash
      # no api exists for complex graph json
      raise NotImplementedError
    end

    def complex?
      true
    end

    def update(args={})
      meta = @parsed_meta.dup
      args.each do |k, v|
        case k
        when 'number' then @number = v
        when 'description' then @description = v
        when 'sort' then @sort = v
        else
          meta[k] = v
        end
      end
      @parsed_meta = self.class.meta_clean(@parsed_meta.merge(meta))
      @meta = JSON.stringify(@parsed_meta)
    end

    def self.meta_clean(args={})
      args.delete_if do |k,v|
        %w(id service_name section_name graph_name number description sort).include?(k.to_s)
      end
    end
  end
end
