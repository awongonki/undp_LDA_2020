# LDA topic modelling of UNDP innovation project descriptions (2020)
# Author: On Ki Wong
#
# Input: an Excel file with one row per paragraph and two columns:
#   ID                   unique paragraph id
#   Cleaned_Translation  paragraph text, translated into English
# The original UNDP data is not included in this repository.

library(textmineR)
library(tidytext)
library(dplyr)
library(tidyr)
library(readxl)
library(ggplot2)

# ---- 1. Load ---------------------------------------------------------------
data <- read_excel("innovation_descriptions.xlsx") |>
  select(ID, Cleaned_Translation) |>
  na.omit()

# ---- 2. Clean --------------------------------------------------------------
# words that are frequent in this corpus but carry no topic information
noise <- c("support", "people", "develop", "developed", "development", "establish",
           "established", "provide", "provided", "providing", "approach", "approaches",
           "increase", "conduct", "process", "test", "tested", "sdg")
pattern <- paste0("\\b(", paste(noise, collapse = "|"), ")\\b")   # whole words only
data$Cleaned_Translation <- gsub(pattern, "", data$Cleaned_Translation, ignore.case = TRUE)

tokens <- data |>
  unnest_tokens(word, Cleaned_Translation) |>
  mutate(word = gsub("[[:digit:]]+|[[:punct:]]+", "", word)) |>
  filter(nchar(word) > 2) |>
  anti_join(stop_words, by = "word") |>
  group_by(ID) |>
  summarise(Cleaned_Translation = paste(word, collapse = " "))

# ---- 3. Document-term matrix (unigrams and bigrams) ------------------------
dtm <- CreateDtm(tokens$Cleaned_Translation,
                 doc_names = tokens$ID,
                 ngram_window = c(1, 2),
                 stem_lemma_function = function(x) SnowballC::wordStem(x, "porter"))
tf <- TermDocFreq(dtm)
# drop terms seen once (too rare) or in more than half of paragraphs (too common)
vocabulary <- tf$term[tf$term_freq > 1 & tf$doc_freq < nrow(dtm) / 2]
dtm <- dtm[, vocabulary]

# ---- 4. Choose the number of topics by probabilistic coherence -------------
set.seed(2020)
models <- lapply(1:20, function(k) {
  m <- FitLdaModel(dtm = dtm, k = k, iterations = 500)
  m$coherence <- CalcProbCoherence(phi = m$phi, dtm = dtm, M = 5)
  m
})
coherence <- data.frame(k = 1:20, coherence = sapply(models, function(m) mean(m$coherence)))

ggplot(coherence, aes(k, coherence)) +
  geom_point() + geom_line() +
  scale_x_continuous(breaks = 1:20) +
  labs(title = "Best number of topics by coherence", y = "Mean coherence") +
  theme_minimal()

best_k <- coherence$k[which.max(coherence$coherence)]   # 16 in the 2020 run
model <- models[[best_k]]

# ---- 5. Top terms per topic -------------------------------------------------
top_terms <- GetTopTerms(phi = model$phi, M = 10)
write.csv(top_terms, "top_terms.csv")

# ---- 6. How close are the topics? Hellinger distance + Ward clustering ------
model$dist <- CalcHellingerDist(model$phi)
model$hclust <- hclust(as.dist(model$dist), "ward.D")
plot(model$hclust, main = "Topic dendrogram (Hellinger distance, Ward linkage)")
