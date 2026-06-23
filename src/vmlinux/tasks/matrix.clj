(ns vmlinux.tasks.matrix
  (:require
   [cheshire.core :as json]
   [manifest :as mf]))

(def ^:private arch-runner {:x86_64 "ubuntu-24.04-32core", :aarch64 "ubuntu-24.04-arm-32core"})

(defn matrix
  []
  {:include (mapv (fn [{:keys [name arch]}] {:name name, :runner (arch-runner arch)}) mf/builds)})

(defn -main [& _] (println (json/generate-string (matrix))))
