require 'spec_helper'

describe ZK::Client::Threaded do
  include_context 'threaded client connection'
  it_should_behave_like 'client'

  describe :close! do
    describe 'from a threadpool thread' do
      it %[should do the right thing and not fail] do
        # this is an extra special case where the user obviously hates us

        @zk.should be_kind_of(ZK::Client::Threaded) # yeah yeah, just be sure

        @zk.defer do
          @zk.close!
        end

        wait_until { @zk.closed? }.should be_true 
      end
    end
  end
end

