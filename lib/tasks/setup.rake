namespace :dokku do
  desc "Generate SSH keypair for Dokku access"
  task :key_setup do
    require 'openssl'
    key_dir = Rails.root.join('config/keys')
    private_key_path = key_dir.join('dokku_rsa')
    public_key_path  = key_dir.join('dokku_rsa.pub')

    FileUtils.mkdir_p(key_dir)
    if File.exist?(private_key_path)
      puts "❗ Key already exists at #{private_key_path}"
      exit(1)
    end

    key = OpenSSL::PKey::RSA.new(2048)
    File.write(private_key_path, key.to_pem)
    File.write(public_key_path, "#{key.ssh_type} #{[key.to_blob].pack('m0')}")
    FileUtils.chmod(0600, private_key_path)

    puts "✅ SSH keypair generated:"
    puts "  Private: #{private_key_path}"
    puts "  Public : #{public_key_path}"
    puts "⚠️  Don’t forget to set DOKKU_SSH_KEY_PATH in your .env file:"
    puts "  DOKKU_SSH_KEY_PATH=#{private_key_path}"
  end
end
