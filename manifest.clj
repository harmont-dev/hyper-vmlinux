(ns manifest)

(defrecord LinuxSpec [name version arch config-file])

(def builds
  [(->LinuxSpec "x86_64-5.10" "5.10.259" :x86_64 "configs/x86_64-5.10.config")
   (->LinuxSpec "x86_64-5.10-no-acpi" "5.10.259" :x86_64 "configs/x86_64-5.10-no-acpi.config")
   (->LinuxSpec "x86_64-6.1" "6.1.176" :x86_64 "configs/x86_64-6.1.config")
   (->LinuxSpec "aarch64-5.10" "5.10.259" :aarch64 "configs/aarch64-5.10.config")
   (->LinuxSpec "aarch64-6.1" "6.1.176" :aarch64 "configs/aarch64-6.1.config")])
