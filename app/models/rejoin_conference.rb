class RejoinConference

	def redirect
		'/calls/check_wait_or_exit'
	end

	def hangupOnStar
		'true'
	end

	def action
		'/calls/confirm_wait'
	end

	def request_method
		'POST'
	end

	def numdigits
		1
	end

	def timeout
		1
	end

end
