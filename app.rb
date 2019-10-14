require 'sinatra'
require 'google/cloud/storage'

storage = Google::Cloud::Storage.new(project_id: 'cs291-f19')

# set the skip_lookup to true cause the user account doesn't have
# permissions to access the bucket permissions
bucket = storage.bucket 'cs291_project2', skip_lookup: true

# regex for sha256 digest validation
valid_sha = /^[0-9a-fA-F]{64}$/
valid_sha_modified = /^[0-9a-fA-F]{2}\/[0-9a-fA-F]{2}\/[0-9a-fA-F]{60}$/

def get_modified_filename(filename)
  modified_hex_digest = filename.dup
  modified_hex_digest = modified_hex_digest.insert(2, "/").insert(5, "/")
  modified_hex_digest.downcase!
  modified_hex_digest
end

get '/' do
  redirect "/files/", 302
end

get '/files/' do
  begin
    files = bucket.files
    files.map! { |item| item.name if item.name.match(valid_sha_modified) != nil }
    files.map! { |item| item.delete! '/' if item != nil }
    files.sort_by! { |a|}
    [200, (files - [nil]).to_json]
  rescue Exception => e
    p "exception occurred in GET/files", e.message
  end
end

post '/files/' do
  begin
    filename = params[:file]
    if filename.nil? or filename == ""
      return [422, "File name not provided"]
    end
    content = params["file"]["tempfile"]
    if content.nil? or !File.file? content
      return [422, "No content found"]
    end
    # data = File.read(content)
    data = content.read
    # check the size of the file
    file_size = File.size(content).to_f / (1024 * 1024)
    if file_size > 1
      return [422, "File greater than 1MB"]
    end
    # modify the name of the object based on the contract defined b/w the user and GCS
    hex_digest = Digest::SHA256.hexdigest data.to_s
    modified_hex_digest = get_modified_filename(hex_digest)
    # fetch the object from the bucket
    file = bucket.file modified_hex_digest
    if file&.exists?
      return [409, "File already exists"]
    end
    temp_file_path = File.absolute_path(params["file"]["tempfile"])
    file = bucket.create_file "#{temp_file_path}", modified_hex_digest, content_type: params["file"]["type"]
    file.content_type
    status 201
    {:uploaded => hex_digest}.to_json

  rescue Exception => e
    p "An exception occurred", e.message
    [500, e.message.to_json]
  end
end

get '/files/:digest' do
  begin
  if params['digest'].match(valid_sha) == nil
    return [422, "Invalid file name"]
  end
  modified_filename = get_modified_filename(params['digest'])
  file = bucket.file modified_filename
  unless file&.exists?
    return [404, "File not found"]
  end
  downloaded_file = file.download
  content = downloaded_file.read
  body =  content
  status 200
  content_type  file.content_type
  body
  rescue Exception => e
    return [500, e.message.to_json]
  end

end

delete '/files/:digest' do
  if params['digest'].match(valid_sha) == nil
    return [422, "Invalid file name".to_json]
  end
  modified_filename = get_modified_filename(params['digest'])
  file = bucket.file modified_filename
  unless file&.exists?
    return [200, "file not found".to_json]
  end
  file.delete
  return [200, "file deleted".to_json]
end