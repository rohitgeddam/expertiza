class User < ApplicationRecord
  extend AnonymizedHelper
  extend UserHelper
  enum locale: Locale.code_name_to_db_encoding(Locale.available_locale_preferences)
  acts_as_authentic do |config|
    config.validates_uniqueness_of_email_field_options = { if: -> { false } } # Don't validate email uniqueness
    config.crypto_provider = Authlogic::CryptoProviders::Sha1
    Authlogic::CryptoProviders::Sha1.join_token = ''
    Authlogic::CryptoProviders::Sha1.stretches = 1
  end
  # Added for E1973. A user can hold a lock on a resource
  has_many :locks, class_name: 'Lock', foreign_key: 'user_id', dependent: :destroy, inverse_of: false
  has_many :participants, class_name: 'Participant', foreign_key: 'user_id', dependent: :destroy
  has_many :assignment_participants, class_name: 'AssignmentParticipant', foreign_key: 'user_id', dependent: :destroy
  has_many :assignments, through: :participants
  has_many :teams_users, dependent: :destroy
  has_many :teams, through: :teams_users
  has_many :sent_invitations, class_name: 'Invitation', foreign_key: 'from_id', dependent: :destroy
  has_many :received_invitations, class_name: 'Invitation', foreign_key: 'to_id', dependent: :destroy
  has_many :children, class_name: 'User', foreign_key: 'parent_id'
  has_many :track_notifications, dependent: :destroy
  belongs_to :parent, class_name: 'User'
  belongs_to :role

  validates :name, presence: true, uniqueness: true, format: { without: /\s/ }
  validates :email,
            presence: { message: "can't be blank" },
            format: { with: /\A[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\z/i, allow_blank: true }
  validates :fullname, presence: true

  before_validation :randomize_password, if: ->(user) { user.new_record? && user.password.blank? } # AuthLogic

  scope :admins, -> { where role_id: Role.administrator }
  scope :instructors, -> { where role_id: Role.instructor }
  scope :tas, -> { where role_id: Role.ta }
  scope :students, -> { where role_id: Role.student }

  has_paper_trail

  def list_mine(object_type, user_id)
    # Takes an object type and a user ID and returns a list of objects owned by the user with the provided ID.
    object_type.where(['instructor_id = ?', user_id])
  end

  def get_visible_users_with_lesser_roles(name)
    lesser_roles = role.get_parents
    all_users = User.all(conditions: ['name LIKE ?', "#{name}%"], limit: 20) # higher limit, since we're filtering
    visible_users = all_users.select { |user| lesser_roles.include? user.role }
    visible_users[0, 10] # the first 10
  end

  def can_impersonate?(user)
    # Takes a user object and returns true if the current user has permission to impersonate the provided user.
    role.super_admin? ||
      teaching_assistant_for?(user) ||
      recursively_parent_of(user)
  end

  def recursively_parent_of(user)
    # Takes a user object and returns true if the current user is the parent or a recursively higher-level parent of the provided user.
    p = user.parent
    unless p.nil? ||
           p.role&.super_admin?
      return p == self ||
             recursively_parent_of(p)
    end
    false
  end

  def get_user_list
    # Returns a list of all users visible to the current user depending on the user's role.
    # If the user is a super admin, all users are returned. If the user is an instructor,
    # all users in their course/assignment are returned.
    # If the user is a TA, all users in their courses are returned.
    # Otherwise, all children of the current user are returned.
    user_list = []
    # If the user is a super admin, fetch all users
    user_list = SuperAdministrator.get_user_list if role.super_admin?

    # If the user is an instructor, fetch all users in his course/assignment
    user_list = Instructor.get_user_list(self) if role.instructor?

    # If the user is a TA, fetch all users in his courses
    user_list = Ta.get_user_list(self) if role.ta?

    # Add the children to the list
    unless role.super_admin?
      User.includes(:parent, :role, parent: %i[parent role]).find_each do |user|
        if recursively_parent_of(user) && !user_list.include?(user)
          user_list << user
        end
      end
    end

    user_list.uniq
  end

  # Zhewei: anonymized view for demo purposes - 1/3/2018

  def name(ip_address = nil)
    User.anonymized_view?(ip_address) ? "#{role.name} #{id.to_s}" : self[:name]
  end

  def fullname(ip_address = nil)
    User.anonymized_view?(ip_address) ? "#{role.name}, #{id.to_s}" : self[:fullname]
  end

  def first_name(ip_address = nil)
    User.anonymized_view?(ip_address) ? role.name : fullname.try(:[], /,.+/).try(:[], /\w+/) || ''
  end

  def email(ip_address = nil)
    User.anonymized_view?(ip_address) ? "#{role.name}_#{id.to_s}@mailinator.com" : self[:email]
  end

  def super_admin?
    role.name == 'Super-Administrator'
  end

  def admin?
    role.name == 'Administrator'
  end

  def student?
    role.name == 'Student'
  end

  # Function which has a MailerHelper which sends the mail welcome email to the user after signing up
  def email_welcome
    # this will send an account creation notification to user via email.
    MailerHelper.send_mail_to_user(self, 'Your Expertiza account and password has been created', 'user_welcome', 
                                   password).deliver_now
  end

  def valid_password?(password)
    Authlogic::CryptoProviders::Sha1.stretches = 1
    # authlogic internally changed the matches function, so old passwords work with the first line
    old_validation = Authlogic::CryptoProviders::Sha1.matches?(crypted_password, password_salt.to_s + password)
    new_validation = Authlogic::CryptoProviders::Sha1.matches?(crypted_password, password, password_salt)
    old_validation || new_validation
  end

  # Resets the password to be mailed to the user
  def reset_password
    randomize_password
    save
    password
  end

  def self.import(row_hash, _row_header, session, _id = nil)
    if row_hash.length < 3
      raise ArgumentError, 
            "Only #{row_hash.length} column(s) is(are) found. It must contain at least username, full name, email."
    end

    user = User.find_by_name(row_hash[:name])
    if user.nil?
      attributes = ImportFileHelper.define_attributes(row_hash)
      user = ImportFileHelper.create_new_user(attributes, session)
    else
      user.email = row_hash[:email]
      user.fullname = row_hash[:fullname]
      user.parent_id = (session[:user]).id
      user.save
    end
    user
  end

  # locate User based on provided login.
  # If user supplies e-mail or name, the
  # helper will try to find that User account.
  def self.find_by_login(login)
    user = User.find_by(email: login)
    if user.nil?
      items = login.split('@')
      short_name = items[0]
      user_list = User.where('name = ?', short_name)
      user = user_list.first if user_list.any? && user_list.length == 1
    end
    user
  end

  def set_instructor(new_assignment)
    # Takes an assignment object and sets the instructor ID to the current user's ID.
    new_assignment.instructor_id = id
  end

  def get_instructor
    id
  end

  def instructor_id
    case role.name
    when 'Super-Administrator' then id
    when 'Administrator' then id
    when 'Instructor' then id
    when 'Teaching Assistant' then Ta.get_my_instructor(id)
    else raise NotImplementedError, "for role #{role.name}"
    end
  end

  # generate a new RSA public/private key pair and create our own X509 digital certificate which we
  # save in the database. The private key is returned by the method but not saved.
  def generate_keys
    # check if we are replacing a digital certificate already generated
    replacing_key = true unless digital_certificate.nil?

    # generate the new key pair
    new_key = OpenSSL::PKey::RSA.generate(1024)
    self.public_key = new_key.public_key.to_pem

    save

    # when replacing an existing key, update any digital signatures made previously with the new key
    if replacing_key
      participants = AssignmentParticipant.where(user_id: id)
      participants.each do |participant|
        participant.assign_copyright(new_key.to_pem) if participant.permission_granted
      end
    end

    # return the new private key
    new_key.to_pem
  end

  def initialize(attributes = nil)
    super(attributes)
    Authlogic::CryptoProviders::Sha1.stretches = 1
    @email_on_review = true
    @email_on_submission = true
    @email_on_review_of_review = true
    @copy_of_emails = false
    @etc_icons_on_homepage = true
  end

  def self.export(csv, _parent_id, options)
    # export csv
    users = User.all
    users.each do |user|
      tcsv = []
      tcsv.push(user.name, user.fullname, user.email) if options['personal_details'] == 'true'
      tcsv.push(user.role.name) if options['role'] == 'true'
      tcsv.push(user.parent.name) if options['parent'] == 'true'
      if options['email_options'] == 'true'
        tcsv.push(user.email_on_submission, user.email_on_review, user.email_on_review_of_review, 
                  user.copy_of_emails)
      end
      tcsv.push(user.etc_icons_on_homepage) if options['etc_icons_on_homepage'] == 'true'
      tcsv.push(user.handle) if options['handle'] == 'true'
      csv << tcsv
    end
  end

  def creator
    parent
  end

  def self.export_fields(options)
    # export the fields in options
    fields = []
    fields.push('name', 'full name', 'email') if options['personal_details'] == 'true'
    fields.push('role') if options['role'] == 'true'
    fields.push('parent') if options['parent'] == 'true'
    if options['email_options'] == 'true'
      fields.push('email on submission', 'email on review', 'email on metareview', 
                  'copy of emails')
    end
    fields.push('preference home flag') if options['etc_icons_on_homepage'] == 'true'
    fields.push('handle') if options['handle'] == 'true'
    fields
  end

  def self.from_params(params)
    user = if params[:user_id]
             User.find(params[:user_id])
           else
             User.find_by name: params[:user][:name]
           end
    if user.nil?
      newuser = url_for controller: 'users', action: 'new'
      raise "Please <a href='#{newuser}'>create an account</a> for this user to continue."
    end
    user
  end

  def teaching_assistant_for?(student)
    return false unless teaching_assistant? &&
                        student &&
                        student.role &&
                        student.role.name == 'Student'

    # We have to use the Ta object instead of User object
    # because single table inheritance is not currently functioning
    ta = Ta.find(id)
    return true if ta.courses_assisted_with.any? do |c|
      c.assignments.map(&:participants).flatten.map(&:user_id).include? student.id
    end
  end

  def teaching_assistant?
    true if role.ta?
  end

  def self.search_users(role, user_id, letter, search_by)
    key_word = { '1' => 'name', '2' => 'fullname', '3' => 'email' }
    sql = "(role_id in (?) or id = ?) and #{key_word[search_by]} like ?"
    if key_word.include? search_by
      search_filter = "%#{letter}%"
      users = User.order('name').where(sql, role.get_available_roles, user_id, search_filter)
    else # default used when clicking on letters
      search_filter = "#{letter}%"
      users = User.order('name').where('(role_id in (?) or id = ?) and name like ?', role.get_available_roles, user_id, 
                                       search_filter)
    end
    users
  end
end
