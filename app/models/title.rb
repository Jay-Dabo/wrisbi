# encoding: utf-8
class Title < ActiveRecord::Base
  belongs_to :party
  has_one :transaction, :through => :party
  has_many :category_links
  has_many :categories, :through => :category_links, :dependent => :destroy
  has_many :operations, :dependent => :destroy, :autosave => true, :inverse_of => :title do
		def update_or_build(account, type_code, amount)
      if account.is_a? ActiveRecord::AssociationRelation
        account = account.first
      end
			if operation = find{|o| o.account == account and o.type_code == type_code }
        if operation.changed?
          # mar egyszer modositottuk ebben a korben;
          # lehetseges, hogy egy szemely adott szamlajara tobb OpShare-t is fel akarunk irni a
          # kategoriak vegett, de ez nem tunik eletszerunek, egyelore nem tamogatjuk, csak elszallunk
          raise "operation is dirty"
        end
				operation.update_attributes(:amount => amount)
				proxy_association.owner.send(:operation_touched, operation.id)
			else
				build(:type_code => type_code, :account => account, :amount => amount)
			end
		end
  end
  has_many :accounts, :through => :operations
  has_many :people, :through => :accounts
  has_many :shares, :autosave => false, :inverse_of => :title do
    def each_amount(base, opts = {})
      Share.each_amount(proxy_association.owner.shares, base, opts) {|share, amount|
        yield(share, amount)
      }
    end
  end
  #belongs_to :applied_business, class_name: 'Business'

  attr_writer :new_category_ids

  accepts_nested_attributes_for :categories, :allow_destroy => true

  # after_save mar nem mukodik az autosave, igy pedig figyelni kell arra, hogy SQL-ben meg nincs ott az
  # asszociacio, emiatt pl az operations.count fail, mig az operations.length mukodik.
  #
  # before_validation az a gond, hogy az input, amibol dolgozik a build_operations meg nincs ellenorizve,
  # before_save pedig az, hogy a legyartott muveleteket mar nem tudjuk ellenorizni [sanity check].
  # Ugyan a manovert a unit teszteknek kellene ellenorizni es igy a sanity check mar folosleges, de
  # a gyakorlat mas.
  before_validation :_set_new_category_ids
  before_validation :_build_shares_and_operations
  after_update do |m|
    if m.party.account_id_changed? or m.amount_changed? or m.comment_changed?
      m.categories.each{|category| category.exporter.after_title_update(m) if category.exporter }
    end
  end

  delegate :treasury, :account, :to => :party

	def changed_for_autosave?
    return true if @rebuild
		return true if party.account_id_changed?
    return true if @new_category_ids
		super
	end

  def rebuild!
    @rebuild = true
    save!
  end

  def self.display_name
    name
  end

  def self.compatible?(party)
    true
  end

  #
  # Kontextus fuggoen akarjuk megjeleniteni;
  # maskepp ha egy adott accountot listazunk es maskepp ha minden manovert
  # pl. /family/titles/_classname
  #
  def to_partial_path
		::File.basename(super)
  end

	#
	# a Rails alapbol nem tamogatja hogy a modell hozza magaval a form-jat, ez ennek a megoldasa
	#
  def to_partial_form_path
		p = []
		klass = self.class
		loop do
			path = File.dirname(klass._to_partial_path)
			paths = [path, ::File.dirname(path.reverse).reverse]
			paths.each do |path|
				if ::File.exists?(Rails.root.to_s+'/app/views/'+path+'/_fields.html.erb')
					return path+'/fields'
				end
			end
			p += paths
			break if not klass.respond_to?(:parent_class)
			klass = klass.parent_class
		end
		raise "Partial template '_fields' not found for %s in: %s" % [self.class.name, p.join(', ')]
  end

  def new_category_ids
    category_ids
  end
  # az "append title" hasznalja
  def category_ids
    @new_category_ids or super
  end

  private
	def _build_shares_and_operations
		build_shares if respond_to?(:build_shares, true)
    @operation_ids_untouched = operation_ids
    build_operations if amount
    #Rails.logger.debug "@operation_ids_untouched: " + @operation_ids_untouched.inspect
		operations.delete(operations.find @operation_ids_untouched) unless @operation_ids_untouched.empty?
	end

  def _set_new_category_ids
    # szerkesztesnel ez azonnal sql muveletet triggerel (tranzakcion kivul), ezert igy csinaljuk
    # kiutni ures tombbel lehet
    self.category_ids = @new_category_ids if @new_category_ids
  end

  def operation_touched(obj_id)
		@operation_ids_untouched.delete(obj_id)
  end

  def amount_could_be_zero?
    false
  end

	def self.parent_class
		ancestors[1..-1].find{|klass| klass.is_a? Class }
	end
end
