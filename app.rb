require 'rubygems'
require 'bundler'
Bundler.setup :default
require 'sinatra'
require 'slim'
require 'omniauth'
require 'omniauth-ncu-portal-openid'
require 'net/ldap'
require 'pony'
require 'rack-session-file'
require './config.rb'

use Rack::Session::File,{
	storage: File.join(File.dirname(__FILE__), 'tmp/session/'),
	expire_after: 18000
}

use OmniAuth::Builder do
	provider :ncu_portal_open_id
end

def dn(cn, ou = Config::LDAP::BASE_OU)
	"cn=%s,ou=%s,%s" % [cn, ou, Config::LDAP::BASE_DC]
end

get '/' do
	slim :index
end

get '/agreement_personal_data' do
	slim :agreement_personal_data
end

get '/apply' do
	redirect to '/apply/step_1'
end

get '/apply/step_1' do
	slim :apply_step_1
end

get '/apply/step_1_portal' do
	session[:portal_login] = :apply
	redirect to '/auth/ncu_portal_open_id'
end

get '/apply/step_2' do
	user = session[:portal_user] || session[:portal_user_past]
	redirect to '/apply' if user.nil?
	# Check if registered
	@uid = user.info[:student_id]
	ldap = Net::LDAP.new host: Config::LDAP::HOST, base: Config::LDAP::BASE_DC
	ldap_search = ldap.search filter: Net::LDAP::Filter.eq("cn", @uid)
	has_registered = ldap_search.length > 0
	redirect to '/apply/registered' if has_registered
	@email = "%s@%s" % [@uid, Config::LDAP::EMAIL_BASE]
	session[:portal_user_past] = session[:portal_user]
	slim :apply_step_2
end

post '/apply/step_2_do' do
	user = session[:portal_user_past]
	redirect to '/apply' if user.nil?
	# TODO: form validate check
	uid = user.info[:student_id]
	@active_code = Digest::MD5.base64digest(Random.rand(Time.now.to_i).to_s)[0..12]
	session[:user_info] = {
		uid: uid,
		sn: params[:english_name].strip.split[1],
		name: [params[:chinese_name].strip, params[:english_name].strip],
		password: Net::LDAP::Password.generate(:sha, params[:password]),
		active_code: @active_code
	}
	Pony.mail({
		:to => "%s@%s" % [uid, Config::LDAP::EMAIL_BASE],
		:from => Config::Gmail::FROM,
		:subject => Config::Gmail::SUBJECT % [uid],
		:body => Config::Gmail::BODY % [@active_code],
		:html_body => slim(Config::Gmail::HTML_BODY, layout: nil),
		:via => :smtp,
		:via_options => {
			:address              => 'smtp.gmail.com',
			:port                 => '587',
			:enable_starttls_auto => true,
			:user_name            => Config::Gmail::ACCOUNT,
			:password             => Config::Gmail::PASSWORD,
			:authentication       => :plain,
			:domain               => Config::Gmail::DOMAIN
		}
	})
	redirect to '/apply/step_3'
end
	
get '/apply/step_3' do
	user = session[:portal_user_past]
	redirect to '/apply' if user.nil?
	uid = user.info[:student_id]
	@email = "%s@%s" % [uid, Config::LDAP::EMAIL_BASE]
	slim :apply_step_3
end

post '/apply/step_3_do' do
	user = session[:portal_user_past]
	redirect to '/apply' if user.nil?
	info = session[:user_info]
	redirect to '/apply' if info.nil?
	session[:user_info] = nil
	redirect to '/apply/failed' if info[:active_code] != params[:active_code].strip
	# LDAP creating account
	ldap = Net::LDAP.new host: Config::LDAP::HOST, base: Config::LDAP::BASE_DC, auth: {
		:method => :simple,
		:username => "cn=%s,%s" % [Config::LDAP::ADMIN_CN, Config::LDAP::BASE_DC],
		:password => Config::LDAP::ADMIN_PW
	}
	last_one = ldap.search(filter: Net::LDAP::Filter.ge('uidNumber', Config::LDAP::UID_BASE.to_s), attributes: [:uidnumber]).sort_by { |account|
		account.uidnumber.first.to_s.to_i
	}.last
	next_uid = last_one.nil? ? Config::LDAP::UID_BASE : (last_one.uidnumber.first.to_s.to_i + 1)
	attr = {
		:cn => info[:uid],
	  :objectclass => ["inetOrgPerson", "posixAccount", "top"],
		:sn => info[:sn], 
		:givenname => info[:name],
		:mail => "%s@%s" % [info[:uid], Config::LDAP::EMAIL_BASE],
		:uidnumber => next_uid.to_s,
		:gidnumber => Config::LDAP::GID.to_s,
		:homedirectory => "/home/users/%s" % [info[:uid]],
		:loginshell => "/bin/sh",
		:uid => info[:uid],
		:userpassword => info[:password]
	}
	ldap.add dn: dn(info[:uid]), attributes: attr
	redirect to '/apply/registered'
end

get '/apply/failed' do
	@user = session[:portal_user] || session[:portal_user_past]
	redirect to '/apply' if @user.nil?
	slim :apply_failed
end

get '/apply/registered' do
	@user = session[:portal_user] || session[:portal_user_past]
	redirect to '/apply' if @user.nil?
	slim :apply_registered
end

[:get, :post].each do |method|
	send method, '/auth/ncu_portal_open_id/callback' do
		case session[:portal_login]
		when :apply
			session[:portal_login] = nil
			session[:portal_user] = request.env['omniauth.auth']
			redirect to '/apply/step_2'
		else
			redirect to '/'
		end
	end
end
