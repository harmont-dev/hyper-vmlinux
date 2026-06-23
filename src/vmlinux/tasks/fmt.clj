(ns vmlinux.tasks.fmt
  (:require [babashka.deps :as deps]
            [babashka.fs :as fs]))

(def ^:private opts {:width 100, :style :community})

(defn- sources [] (map str (fs/glob "." "{src/**/*.clj,manifest.clj}")))

(defn -main
  [& args]
  (deps/add-deps '{:deps {zprint/zprint {:mvn/version "1.2.9"}}})
  (let [zprint (requiring-resolve 'zprint.core/zprint-file-str)
        reformat (fn [f] (zprint (slurp f) f opts))]
    (if (= "check" (first args))
      (let [bad (filterv (fn [f] (not= (slurp f) (reformat f))) (sources))]
        (when (seq bad) (run! (fn [f] (println "needs formatting:" f)) bad) (System/exit 1))
        (println "format OK"))
      (doseq [f (sources)] (spit f (reformat f))))))
