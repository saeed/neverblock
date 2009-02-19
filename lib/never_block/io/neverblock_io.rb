require 'rubygems'
require File.expand_path(File.dirname(__FILE__) + "/fibered_io_connection")


# This is an extention to the Ruby IO class that makes it compatable with
#	NeverBlocks event loop to avoid blocking IO calls. That's done by delegating
#	all the reading methods to read_nonblock and all the writting methods to
#	write_nonblock. 

class IO

	include NeverBlock::IO::FiberedIOConnection

	NB_BUFFER_LENGTH = 1024
  alias_method :read_blocking, :sysread
  alias_method :write_blocking, :syswrite

	attr_accessor :immediate_result

	def buffer
	 @buffer ||= ""
	end

	def get_reading_result
		@reading_result
	end
		

	#	This method is the delegation method which reads using read_nonblock()
	#	and registers the IO call with event loop if the call blocks. The value
	# @immediate_result is used to get the value that method got before it was blocked.


  def read_neverblock(*args)
		res = ""
		begin
			raise Timeout::Error if Fiber.current[:exceeded_timeout]
			@immediate_result = read_nonblock(*args)
			res << @immediate_result
		rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
  		attach_to_reactor(:read)
  		retry
		end
		res
  end

	#	The is the main reading method that all other methods use.
	#	If the mode is set to neverblock it uses the delegation method.
	#	Otherwise it uses the original ruby read method.

  def sysread(*args)
		if Fiber.current[:neverblock]
			res = read_neverblock(*args)
    else
      res = read_blocking(*args)
    end
		res
  end
  
  def read(length=0, sbuffer=nil)
		return '' if length == 0
		unless buffer.length > length
			begin 
				buffer << sysread(NB_BUFFER_LENGTH > length ? NB_BUFFER_LENGTH : length, sbuffer)
				sbuffer.slice!(length..sbuffer.length-1) if !sbuffer.nil?
			rescue EOFError
				return nil
			end
		end
		buffer.slice!(0..length-1)
  end

  def write_neverblock(data)
		written = 0
		begin
			raise Timeout::Error if Fiber.current[:exceeded_timeout]
			written = written + write_nonblock(data[written,data.length])
			raise Errno::EAGAIN if written < data.length
		rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
  		attach_to_reactor(:read)
			retry
	end
		written
  end

	def syswrite(*args)	
		if Fiber.current[:neverblock]
			write_neverblock(*args)
		else
			write_blocking(*args)
		end
	end
  
	def write(*args)
		syswrite(*args)
	end 
	
	def gets(*args)
		res = ""
		args[0] = "\n\n" if args[0] == ""
		if args.length == 0
			condition = proc{|res|res.index("\n").nil?}
		elsif args.length == 1
			if args[0] == nil
				condition = proc{|res|true}		
			else
				condition = proc{|res|res.index(args[0]).nil?}
			end
		elsif args.length == 2
			count = args[1]
			if args[0] == nil
				condition = proc{|res| count = count - 1; count > -1}
			else 
				condition = proc{|res| count = count - 1; count > -1 && res.index(args[0]).nil?}
			end
		end
		begin		
			while condition.call(res)
			  res << read(1)
			end
		rescue EOFError
		end
		res
	end
	
	def readlines
		res = []
		begin
			loop{res << readline}
		rescue EOFError
		end
		res
	end
	
	def readchar
		sysread(1)[0]
	end
	
	def getc
		begin
			res = readchar
		rescue EOFError
			res = nil
		end
	end

	def readline(sep = "\n")
		res = gets(sep)
		raise EOFError if res == nil
		res
	end

	def readbytes(*args)
		sysread(*args)
	end
	
	def print(*args)
		args.each{|element|syswrite(element)}
	end
end
