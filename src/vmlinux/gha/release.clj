(ns vmlinux.gha.release
  (:require
   [babashka.fs :as fs]
   [babashka.process :refer [shell]]
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

(defn create
  [sha assets]
  (let [tag (release-tag sha)]
    (when-not (exists? sha)
      (shell "gh" "release" "create" tag "--title" (title sha) "--notes" (notes sha)))
    (->> assets
         (mapv (fn [build]
                 (future (let [asset (str (fs/parent (:binary-path build)) "/" (asset-name build))]
                           (fs/copy (:binary-path build) asset {:replace-existing true})
                           (upload! tag asset)))))
         (run! deref))
    tag))
