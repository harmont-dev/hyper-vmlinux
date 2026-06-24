(ns vmlinux.gha.release
  (:require
   [babashka.fs :as fs]
   [babashka.process :refer [shell]]
   [cheshire.core :as json]
   [selmer.parser :as p]))

(defn- release-tag [sha] (str "release-" sha))

(defn- title [sha] (p/render "Hyper Firecracker Linux Images {{sha}}" {:sha sha}))

(defn- notes
  [sha]
  (p/render
   "VMLinux images used within [Hyper](https://github.com/harmont-dev/hyper) built off of `{{sha}}`."
   {:sha sha}))

(defn- asset-name [{:keys [name]}] (str "vmlinux-" name))

(defn exists?
  [sha]
  (-> (shell {:continue true, :out :string, :err :string} "gh" "release" "view" (release-tag sha))
      :exit
      zero?))

(defn- upload!
  [tag asset]
  (loop [attempt 1]
    (let [exit (:exit (shell {:continue true} "gh" "release" "upload" tag asset))]
      (cond (zero? exit) :ok
            (< attempt 6) (do (Thread/sleep (* attempt 2000)) (recur (inc attempt)))
            :else (throw (ex-info (str "gh release upload failed for " asset) {:asset asset}))))))

(defn- stage-asset!
  "Copy the build binary to its release asset name and write a `<asset>.sha256`
  sidecar in sha256sum(1) format. Returns the [asset sidecar] paths."
  [build]
  (let [name (asset-name build)
        asset (str (fs/parent (:binary-path build)) "/" name)
        sidecar (str asset ".sha256")]
    (fs/copy (:binary-path build) asset {:replace-existing true})
    (spit sidecar (str (:sha256-sum build) "  " name "\n"))
    [asset sidecar]))

(defn- manifest-json
  [sha assets]
  (json/generate-string {:sha sha,
                         :builds (mapv (fn [{:keys [name arch version sha256-sum], :as build}]
                                         {:name name,
                                          :arch (clojure.core/name arch),
                                          :version version,
                                          :asset (asset-name build),
                                          :sha256 sha256-sum})
                                       assets)}
                        {:pretty true}))

(defn create
  [sha assets]
  (let [tag (release-tag sha)]
    (when-not (exists? sha)
      (shell "gh" "release" "create" tag "--title" (title sha) "--notes" (notes sha)))
    (->> assets
         (mapv (fn [build]
                 (future (let [[asset sidecar] (stage-asset! build)]
                           (upload! tag asset)
                           (upload! tag sidecar)))))
         (run! deref))
    (let [manifest (str (fs/parent (:binary-path (first assets))) "/manifest.json")]
      (spit manifest (manifest-json sha assets))
      (upload! tag manifest))
    tag))
