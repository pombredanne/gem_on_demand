require "spec_helper"

describe GemOnDemand do
  let(:config) { YAML.load_file("spec/config.yml") if File.exist?("spec/config.yml") }

  def with_config
    if config
      yield
    else
      pending "No spec/config.yml"
    end
  end

  describe ".build_gem" do
    it "can build gem" do
      gem = GemOnDemand.build_gem("grosser", "parallel", "0.9.2")
      gem.size.should >= 2000
    end

    it "can build with outdated gem cert" do
      gem = GemOnDemand.build_gem("grosser", "parallel", "0.8.4")
      gem.size.should >= 2000
    end
  end

  describe ".dependencies" do
    it "lists all dependencies" do
      dependencies = GemOnDemand.dependencies("grosser", ["parallel_tests"])
      dependencies.last.should include(
        :name=>"parallel_tests",
        :platform=>"ruby",
        :dependencies=>[["parallel", ">= 0"]]
      )
      dependencies.size.should >= 50
    end

    it "lists dependencies for private repo" do
      with_config do
        dependencies = GemOnDemand.dependencies(config[:private][:user], [config[:private][:project]])
        dependencies.last.should include config[:private][:dependencies]
      end
    end

    it "lists nothing when gems are not found" do
      dependencies = GemOnDemand.dependencies("grosser", ["missing"])
      dependencies.should == []
    end
  end
end
