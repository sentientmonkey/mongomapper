module MongoMapper
  module Document
    extend Support::DescendantAppends

    def self.included(model)
      model.class_eval do
        include InstanceMethods
        extend  Support::Find
        extend  ClassMethods
        extend  Plugins

        plugin Plugins::Associations
        plugin Plugins::Clone
        plugin Plugins::Descendants
        plugin Plugins::Equality
        plugin Plugins::Inspect
        plugin Plugins::Keys
        plugin Plugins::Dirty # for now dirty needs to be after keys
        plugin Plugins::Logger
        plugin Plugins::Modifiers
        plugin Plugins::Pagination
        plugin Plugins::Persistence
        plugin Plugins::Protected
        plugin Plugins::Rails
        plugin Plugins::Serialization
        plugin Plugins::Timestamps
        plugin Plugins::Userstamps
        plugin Plugins::Validations
        plugin Plugins::Callbacks # for now callbacks needs to be after validations
        plugin Plugins::QueryLogger

        extend Plugins::Validations::DocumentMacros
      end

      super
    end

    module ClassMethods
      def inherited(subclass)
        subclass.set_collection_name(collection_name)
        super
      end

      def ensure_index(spec, options={})
        collection.create_index(spec, options)
      end

      def find(*args)
        assert_no_first_last_or_all(args)
        options = args.extract_options!
        return nil if args.size == 0

        if args.first.is_a?(Array) || args.size > 1
          find_some(args, options)
        else
          find_one(options.merge({:_id => args[0]}))
        end
      end

      def find!(*args)
        assert_no_first_last_or_all(args)
        options = args.extract_options!
        raise DocumentNotFound, "Couldn't find without an ID" if args.size == 0

        if args.first.is_a?(Array) || args.size > 1
          find_some!(args, options)
        else
          find_one(options.merge({:_id => args[0]})) || raise(DocumentNotFound, "Document match #{options.inspect} does not exist in #{collection.name} collection")
        end
      end

      def find_each(options={})
        criteria, options = to_query(options)
        collection.find(criteria, options).each do |doc|
          yield load(doc)
        end
      end

      def find_by_id(id)
        find(id)
      end

      def first_or_create(args)
        first(args) || create(args.reject { |key, value| !key?(key) })
      end

      def first_or_new(args)
        first(args) || new(args.reject { |key, value| !key?(key) })
      end

      def first(options={})
        find_one(options)
      end

      def last(options={})
        raise ':order option must be provided when using last' if options[:order].blank?
        find_one(options.merge(:order => invert_order_clause(options[:order])))
      end

      def all(options={})
        find_many(options)
      end

      def count(options={})
        collection.find(to_criteria(options)).count
      end

      def exists?(options={})
        !count(options).zero?
      end

      def create(*docs)
        initialize_each(*docs) { |doc| doc.save }
      end

      def create!(*docs)
        initialize_each(*docs) { |doc| doc.save! }
      end

      def update(*args)
        if args.length == 1
          update_multiple(args[0])
        else
          id, attributes = args
          update_single(id, attributes)
        end
      end

      def delete(*ids)
        collection.remove(to_criteria(:_id => ids.flatten))
      end

      def delete_all(options={})
        collection.remove(to_criteria(options))
      end

      def destroy(*ids)
        find_some!(ids.flatten).each(&:destroy)
      end

      def destroy_all(options={})
        find_each(options) { |document| document.destroy }
      end

      def embeddable?
        false
      end

      def single_collection_inherited?
        keys.key?(:_type) && single_collection_inherited_superclass?
      end

      def single_collection_inherited_superclass?
        superclass.respond_to?(:keys) && superclass.keys.key?(:_type)
      end

      private
        def initialize_each(*docs)
          instances = []
          docs = [{}] if docs.blank?
          docs.flatten.each do |attrs|
            doc = new(attrs)
            yield(doc)
            instances << doc
          end
          instances.size == 1 ? instances[0] : instances
        end

        def assert_no_first_last_or_all(args)
          if args[0] == :first || args[0] == :last || args[0] == :all
            raise ArgumentError, "#{self}.find(:#{args}) is no longer supported, use #{self}.#{args} instead."
          end
        end

        def find_some(ids, options={})
          ids = ids.flatten.compact.uniq
          find_many(options.merge(:_id => ids)).compact
        end

        def find_some!(ids, options={})
          ids = ids.flatten.compact.uniq
          documents = find_some(ids, options)

          if ids.size == documents.size
            documents
          else
            raise DocumentNotFound, "Couldn't find all of the ids (#{ids.to_sentence}). Found #{documents.size}, but was expecting #{ids.size}"
          end
        end

        # All query methods that load documents pass through find_one or find_many
        def find_one(options={})
          criteria, options = to_query(options)
          if doc = collection.find_one(criteria, options)
            load(doc)
          end
        end

        # All query methods that load documents pass through find_one or find_many
        def find_many(options)
          criteria, options = to_query(options)
          collection.find(criteria, options).to_a.map do |doc|
            load(doc)
          end
        end

        def invert_order_clause(order)
          order.split(',').map do |order_segment|
            if order_segment =~ /\sasc/i
              order_segment.sub /\sasc/i, ' desc'
            elsif order_segment =~ /\sdesc/i
              order_segment.sub /\sdesc/i, ' asc'
            else
              "#{order_segment.strip} desc"
            end
          end.join(',')
        end

        def update_single(id, attrs)
          if id.blank? || attrs.blank? || !attrs.is_a?(Hash)
            raise ArgumentError, "Updating a single document requires an id and a hash of attributes"
          end

          doc = find(id)
          doc.update_attributes(attrs)
          doc
        end

        def update_multiple(docs)
          unless docs.is_a?(Hash)
            raise ArgumentError, "Updating multiple documents takes 1 argument and it must be hash"
          end

          instances = []
          docs.each_pair { |id, attrs| instances << update(id, attrs) }
          instances
        end

        def to_criteria(options={})
          Query.new(self, options).criteria
        end

        def to_query(options={})
          Query.new(self, options).to_a
        end
    end

    module InstanceMethods
      def save(options={})
        options.assert_valid_keys(:validate, :safe)
        options.reverse_merge!(:validate => true)
        !options[:validate] || valid? ? create_or_update(options) : false
      end

      def save!(options={})
        options.assert_valid_keys(:safe)
        save(options) || raise(DocumentNotValid.new(self))
      end

      def destroy
        delete
      end

      def delete
        @_destroyed = true
        self.class.delete(id) unless new?
      end

      def new?
        @new
      end

      def destroyed?
        @_destroyed == true
      end

      def reload
        if attrs = collection.find_one({:_id => _id})
          self.class.associations.each { |name, assoc| send(name).reset if respond_to?(name) }
          self.attributes = attrs
          self
        else
          raise DocumentNotFound, "Document match #{_id.inspect} does not exist in #{collection.name} collection"
        end
      end

      # Used by embedded docs to find root easily without if/respond_to? stuff.
      # Documents are always root documents.
      def _root_document
        self
      end

    private
      def create_or_update(options={})
        result = new? ? create(options) : update(options)
        result != false
      end

      def create(options={})
        save_to_collection(options)
      end

      def update(options={})
        save_to_collection(options)
      end

      def save_to_collection(options={})
        safe = options[:safe] || false
        @new = false
        collection.save(to_mongo, :safe => safe)
      end
    end
  end # Document
end # MongoMapper
