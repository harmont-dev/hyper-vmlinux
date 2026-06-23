(ns vmlinux.tasks.matrix
  (:require
   [cheshire.core :as json]
   [manifest :as mf]))

(def ^:private arch-runner {:x86_64 "ultralarge-24.04-x64", :aarch64 "ultralarge-24.04-aarch64"})

(defn matrix
  []
  {:include (mapv (fn [{:keys [name arch]}] {:name name, :runner (arch-runner arch)}) mf/builds)})

(defn -main [& _] (println (json/generate-string (matrix))))
