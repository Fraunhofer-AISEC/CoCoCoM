# Copyright 2020-2021 Joana Pecholt, Fraunhofer AISEC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM debian:buster-slim

# The fewer commands / RUNs are here, the better
RUN apt-get update && apt-get install -y \
  python3 \
  wget \
  iproute2 \
  iputils-ping

# Expose port
EXPOSE 7777

# setup
COPY startup.sh /root/

# start
CMD ["/root/startup.sh"]

# CALL docker run --name=test-instance -d -p 8000:7777 my-container