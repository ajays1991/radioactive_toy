require "aws-sdk-s3"
require "json"

module RadioactiveToy
	class S3Provisioner
		attr_reader :aws_s3, :bucket, :key

		def initialize(region:, bucket:, key:)
			@aws_s3 = Aws::S3::Client.new(
			  region: region
			)
		end

		def read_file
			response = aws_s3.get_object(
			  bucket: bucket,
			  key: key
			)

			json_data = JSON.parse(response.body.read)

			puts json_data
		end

		def save_file(data)
			aws_s3.put_object(
			  bucket: bucket,
			  key: key,
			  body: JSON.pretty_generate(data),
			  content_type: 'application/json'
			)
		end
	end
end