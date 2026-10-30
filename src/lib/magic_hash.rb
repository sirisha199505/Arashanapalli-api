class MagicHash < Hash
  def self.magic
    new do |hash, key|
      hash[key] = new(&hash.default_proc)
    end
  end
end