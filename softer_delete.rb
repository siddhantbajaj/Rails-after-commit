
require "active_support"
require "active_support/concern"

module SofterDelete
  module Common
    extend ActiveSupport::Concern

    included do
      default_scope { not_deleted }
      after_destroy :populate_soft_delete_attributes, prepend: true
    end

    def destroyed?
      # We must respect original destroyed? behavior otherwise after_commit callbacks won't fire
      (super || deleted?) && !defined?(@_save_ignoring_soft_deletion)
    end

    def deletable?
      !deleted?
    end

    def reload(*)
      @destroyed = nil
      super
    end

    def destroy
      return false unless deletable?
      prepare_for_soft_delete do
        super
      end
    end

    def freeze
      super unless soft_delete_attributes
      self
    end

    def save_ignoring_soft_deletion(*args, &block)
      @_save_ignoring_soft_deletion = true
      save(*args, &block)
    ensure
      remove_instance_variable(:@_save_ignoring_soft_deletion)
    end

    def save_ignoring_soft_deletion!(*args, &block)
      @_save_ignoring_soft_deletion = true
      save!(*args, &block)
    ensure
      remove_instance_variable(:@_save_ignoring_soft_deletion)
    end

    def update_columns_ignoring_soft_deletion(attributes)
      @_save_ignoring_soft_deletion = true
      update_columns(attributes)
    ensure
      remove_instance_variable(:@_save_ignoring_soft_deletion)
    end

    private

    def destroy_row
      relation = if locking_enabled?
        locking_column = self.class.locking_column
        self.class.unscoped.where(
          self.class.primary_key => id, locking_column => read_attribute_before_type_cast(locking_column)
        )
      else
        self.class.unscoped.where(self.class.primary_key => id)
      end

      affected_rows = relation.not_deleted.update_all(soft_delete_attributes)

      if affected_rows != 1 && locking_enabled?
        raise ActiveRecord::StaleObjectError.new(self, "destroy")
      end

      if affected_rows > 0
        each_counter_cached_associations do |association|
          foreign_key = association.reflection.foreign_key.to_sym
          unless destroyed_by_association && destroyed_by_association.foreign_key.to_sym == foreign_key
            if send(association.reflection.name)
              association.decrement_counters
            end
          end
        end
      end

      affected_rows
    end

    attr_reader :soft_delete_attributes

    def prepare_for_soft_delete
      now = current_time_from_proper_timezone
      params = { deleted_at: now }
      params[:updated_at] = now if has_attribute?(:updated_at)
      params[:is_deleted] = true if has_attribute?(:is_deleted)
      params[:is_not_deleted] = nil if has_attribute?(:is_not_deleted)
      @soft_delete_attributes = params
      return yield
    ensure
      @soft_delete_attributes = nil
    end

    def populate_soft_delete_attributes
      assign_attributes(soft_delete_attributes)
    end
  end

  module UsingIsDeleted
    extend ActiveSupport::Concern

    included do
      include SofterDelete::Common
      scope :deleted, -> { ignoring_soft_deletion.where(is_deleted: true) }
      scope :not_deleted, -> { where(is_deleted: false) }
      scope :ignoring_soft_deletion, -> { unscope(where: :is_deleted) }
    end

    def deleted?
      is_deleted
    end
  end

  module UsingIsNotDeleted
    extend ActiveSupport::Concern

    included do
      include SofterDelete::Common
      scope :deleted, -> { ignoring_soft_deletion.where(is_not_deleted: nil) }
      scope :not_deleted, -> { where(is_not_deleted: true) }
      scope :ignoring_soft_deletion, -> { unscope(where: :is_not_deleted) }
    end

    def deleted?
      !self.is_not_deleted
    end
  end
end