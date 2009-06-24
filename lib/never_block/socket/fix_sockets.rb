require 'socket'

Object.send(:remove_const, :TCPSocket)

class TCPSocket < Socket
  
  alias_method :recv_blocking, :recv

	def initialize(*args)
    super(AF_INET, SOCK_STREAM, 0)
    self.connect(Socket.sockaddr_in(*(args.reverse)))
  end


	def recv_neverblock(*args)
		res = ""
		begin
			@immediate_result = recv_nonblock(*args)
			res << @immediate_result
		rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
  		attach_to_reactor(:read)
  		retry
		end
		res
  end

	def recv(*args)
		if Fiber.current[:neverblock]
			res = recv_neverblock(*args)
    else
      res = recv_blocking(*args)
    end
		res
  end

end

class BasicSocket
  @@getaddress_method = IPSocket.method(:getaddress)
  def self.getaddress(*args)
    @@getaddress_method.call(*args)
  end
end
