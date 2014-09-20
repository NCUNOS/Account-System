module Config
	module LDAP
		HOST = '10.20.30.40'
		BASE_DC = 'dc=domain,dc=tld'
		BASE_OU = 'users'
		UID_BASE = 10000
		GID = 10000
		EMAIL_BASE = 'domain.tld'
		ADMIN_CN = 'root'
		ADMIN_PW = 'r00t p455w0rd'
	end

	module Gmail
		DOMAIN = 'account.domain.tld'
		ACCOUNT = 'account_system@gmail.com'
		PASSWORD = '9m4!1_p455w0rd'
		FROM = '中央大學網路開源社帳號系統 <%s>' % [ACCOUNT]
		SUBJECT = '[確認碼] 帳號： %s 啓用確認碼'
		BODY = '您的啓用確認碼為： %s'
		HTML_BODY = :mail_active
	end
end
